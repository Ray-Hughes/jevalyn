# frozen_string_literal: true

require "json"

module Jevalyn
  # Keeps test suites off the network.
  #
  # TypeSafe has no sandbox key or mock endpoint, so `mock_mode` is entirely local:
  # with it on, Client never opens a connection and answers come from here instead.
  #
  #   Jevalyn::Testing.stub(SupportTriage, department: :technical, urgent: true)
  #
  #   result = SupportTriage.evaluate("payouts failing")
  #   result.department   # => :technical
  #
  # Values are written the way you would assert on them -- `true`, `:technical`,
  # `"major"` -- and Testing expands each into a response the real API could have
  # returned, probability distribution and all.
  module Testing
    # How lopsided a stubbed distribution is. High enough to clear a realistic
    # confidence threshold without being a fake 1.0 that no real model ever returns.
    DEFAULT_CONFIDENCE = 0.95

    # What a stubbed `true` and `false` become.
    DEFAULT_NOUL_TRUE  = 0.95
    DEFAULT_NOUL_FALSE = 0.05

    Call = Struct.new(:decision, :state, :questions, :model, :raw, keyword_init: true)

    class NoStubError < Error; end

    class << self
      # Every evaluation made in mock mode, oldest first.
      def calls
        store[:calls] ||= []
      end

      # Registers answers for a Decision.
      #
      #   Jevalyn::Testing.stub(SupportTriage, urgent: true, department: :technical)
      #   Jevalyn::Testing.stub(SupportTriage, confidence: 0.6, department: :billing)
      #   Jevalyn::Testing.stub(SupportTriage) { |state| { department: route_for(state) } }
      #
      # `confidence:` also takes a Hash, which is how you exercise per-question floors:
      # one answer landing under its floor while another clears its own.
      #
      #   Jevalyn::Testing.stub(SupportTriage,
      #     department: :technical, severity: "major",
      #     confidence: { department: 0.7, severity: 0.65 })
      #
      # A block is re-run per call and receives the serialised state, so one stub can
      # answer differently for different inputs.
      def stub(decision, confidence: DEFAULT_CONFIDENCE, **values, &block)
        stubs[key_for(decision)] = { values: values, confidence: confidence, block: block }
        decision
      end

      # A catch-all for decisions with no stub of their own.
      def stub_any(confidence: DEFAULT_CONFIDENCE, **values, &block)
        stubs[:__any__] = { values: values, confidence: confidence, block: block }
      end

      # Raises instead of answering, to prove a code path does not call Jev.
      def forbid(decision)
        stubs[key_for(decision)] = :forbidden
      end

      def stubbed?(decision) = stubs.key?(key_for(decision))

      def reset!
        store[:stubs] = {}
        store[:calls] = []
        store[:cassette] = nil
      end

      # Called by Client when config.mock_mode is on. Returns a raw response Hash.
      def answer(body:, questions:, decision: nil)
        raw = cassette&.fetch(body) || build_response(body: body, questions: questions, decision: decision)

        calls << Call.new(
          decision: decision, state: body["state"], questions: questions,
          model: body["model"], raw: raw
        )

        raw
      end

      # Wraps a real API call in whatever cassette is currently installed: replays a
      # recorded response when there is one, records the live answer when there is not.
      def through_cassette(body)
        active = cassette
        return yield unless active

        active.fetch(body) || active.record(body, yield)
      end

      # Stand-in for GET /v1/models.
      def models
        [
          { "name" => "jev-latest",  "description" => "Most recent stable release" },
          { "name" => "jev-preview", "description" => "Most recent release, stable or not" }
        ]
      end

      # Turns friendly values into a response body the API could have produced.
      def build_response(body:, questions:, decision: nil)
        entry = stub_for(decision)

        if entry == :forbidden
          raise NoStubError,
                "#{decision} is forbidden in this example, but something evaluated it."
        end

        values, confidence = resolve(entry, body)

        answers = questions.each_with_object({}) do |(name, question), out|
          raise NoStubError, missing_message(decision, name, questions) unless values.key?(name)

          out[name.to_s] = answer_for(question, values[name], confidence_for(confidence, name))
        end

        {
          "model" => body["model"] == "jev-latest" ? "jev-1.13.0" : body["model"],
          "answers" => answers,
          "usage" => { "input_tokens" => State.estimated_tokens(body["state"]), "output_tokens" => 0 }
        }
      end

      # Builds one answer object of the right shape for a question type.
      def answer_for(question, value, confidence)
        case question.type
        when :noul   then noul_answer(value)
        when :choice then choice_answer(question, value, confidence)
        when :score  then score_answer(question, value, confidence)
        end
      end

      private

      # `confidence:` is either one number for every answer, or a Hash naming them
      # individually so a spec can put one answer under its floor and another over.
      def confidence_for(confidence, name)
        return confidence unless confidence.is_a?(Hash)

        confidence[name] || confidence[name.to_s] || DEFAULT_CONFIDENCE
      end

      def noul_answer(value)
        probability =
          case value
          when true     then DEFAULT_NOUL_TRUE
          when false    then DEFAULT_NOUL_FALSE
          when Numeric  then value.to_f
          else
            raise ArgumentError,
                  "A noul stub takes true, false or a Float between 0 and 1, got #{value.inspect}."
          end

        { "type" => "noul", "noul" => probability.round(6) }
      end

      def choice_answer(question, value, confidence)
        chosen = value.to_s
        options = question.criteria.keys.map(&:to_s)

        unless options.include?(chosen)
          raise ArgumentError,
                "#{chosen.inspect} is not an option of :#{question.name}. " \
                "It accepts: #{options.map(&:inspect).join(", ")}."
        end

        {
          "type" => "choice",
          "choice" => chosen,
          "probabilities" => distribute(options, chosen, confidence),
          "confidence" => confidence.to_f.round(6)
        }
      end

      def score_answer(question, value, confidence)
        levels = question.levels
        index =
          case value
          when Integer then value
          when Float   then value.round
          when String, Symbol
            found = levels.index(value.to_s)
            unless found
              raise ArgumentError,
                    "#{value.inspect} is not a level of :#{question.name}. " \
                    "It has: #{levels.map(&:inspect).join(", ")}."
            end
            found
          else
            raise ArgumentError,
                  "A score stub takes a level name, or its index, got #{value.inspect}."
          end

        unless index.between?(0, levels.length - 1)
          raise ArgumentError,
                "Level #{index} is out of range for :#{question.name} (0..#{levels.length - 1})."
        end

        keys = (0...levels.length).map(&:to_s)
        probabilities = distribute(keys, index.to_s, confidence)
        # The real API returns a probability-weighted score, so do the same arithmetic
        # here -- a stub that always returns a whole number hides rounding bugs.
        weighted = probabilities.sum { |level, probability| level.to_i * probability }

        {
          "type" => "score",
          "score" => weighted.round(6),
          "legend" => keys.zip(levels).to_h,
          "probabilities" => probabilities,
          "confidence" => confidence.to_f.round(6)
        }
      end

      # Puts `confidence` of the mass on the winner and spreads the rest evenly.
      def distribute(keys, winner, confidence)
        confidence = confidence.to_f.clamp(0.0, 1.0)
        others = keys - [winner]
        remainder = others.empty? ? 0.0 : (1.0 - confidence) / others.length

        keys.to_h { |key| [key, (key == winner ? confidence : remainder).round(6)] }
      end

      def resolve(entry, body)
        unless entry
          raise NoStubError, <<~MSG.strip
            Jevalyn is in mock_mode and nothing is stubbed for this evaluation.

              Jevalyn::Testing.stub(YourDecision, question_name: value)

            Or allow real calls in this example with `Jevalyn.config.mock_mode = false`.
          MSG
        end

        values = entry[:values] || {}
        values = values.merge(entry[:block].call(body["state"]) || {}) if entry[:block]
        [symbolize(values), entry[:confidence] || DEFAULT_CONFIDENCE]
      end

      def stub_for(decision)
        stubs[key_for(decision)] || stubs[:__any__]
      end

      def missing_message(decision, name, questions)
        <<~MSG.strip
          No stubbed value for :#{name} on #{decision || "this evaluation"}.

            Jevalyn::Testing.stub(#{decision || "YourDecision"}, #{questions.keys.map { |k| "#{k}: ..." }.join(", ")})
        MSG
      end

      def symbolize(hash)
        hash.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
      end

      def key_for(decision)
        decision.is_a?(Class) ? decision.name || decision.object_id : decision.to_s
      end

      def cassette = store[:cassette]

      def stubs
        store[:stubs] ||= {}
      end

      # Thread-local so parallel specs do not stub over each other.
      def store
        Thread.current[:jevalyn_testing] ||= {}
      end
    end
  end
end
