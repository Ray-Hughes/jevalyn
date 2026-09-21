# frozen_string_literal: true

module Jevalyn
  # A named set of questions your app asks about a piece of state.
  #
  #   class SupportTriage < Jevalyn::Decision
  #     question :urgent, type: :noul,
  #       instructions: "Does this convey urgency?"
  #
  #     question :department, type: :choice,
  #       instructions: "Which team should handle this?",
  #       criteria: {
  #         billing:   "Payments, invoicing, refunds",
  #         technical: "Bugs, outages, integrations",
  #         sales:     "Pricing, upgrades, new accounts"
  #       }
  #
  #     confidence_threshold 0.75
  #   end
  #
  #   result = SupportTriage.evaluate(ticket.body)
  #   result.department   # => :technical
  #   result.certain?     # => true
  #
  # Every question is validated when the class body runs, so a rubric with eleven
  # score levels fails on boot rather than as a 422 on a Friday afternoon.
  class Decision
    class << self
      # Declares one question. Keys map one-to-one onto the API's question object,
      # except `confidence_threshold`, which is Jevalyn's and is never sent.
      def question(name, type:, instructions:, criteria: nil, confidence_threshold: nil)
        name = name.to_sym

        if questions.key?(name)
          raise InvalidQuestionError,
                "#{self.name || "Decision"} already declares a question named :#{name}."
        end

        own_questions[name] = Question.build(name, type: type, instructions: instructions, criteria: criteria)
        unless confidence_threshold.nil?
          own_thresholds[name] =
            validate_threshold!(confidence_threshold,
                                "confidence_threshold for :#{name}")
        end
        reset_result_class!
        own_questions[name]
      end

      # Sugar for the three types. `noul :urgent, "Does this convey urgency?"`
      def noul(name, instructions, criteria: nil, confidence_threshold: nil)
        question(name, type: :noul, instructions: instructions, criteria: criteria,
                       confidence_threshold: confidence_threshold)
      end

      def choice(name, instructions, criteria, confidence_threshold: nil)
        question(name, type: :choice, instructions: instructions, criteria: criteria,
                       confidence_threshold: confidence_threshold)
      end

      def score(name, instructions, criteria, confidence_threshold: nil)
        question(name, type: :score, instructions: instructions, criteria: criteria,
                       confidence_threshold: confidence_threshold)
      end

      # Reads or sets the default confidence floor for this decision's questions.
      # A question that declares its own overrides this; see #confidence_threshold_for.
      # Called with no argument it reads; the inherited or global value is the fallback.
      def confidence_threshold(value = :__read__)
        if value == :__read__
          return @confidence_threshold if defined?(@confidence_threshold) && @confidence_threshold
          return superclass.confidence_threshold if superclass.respond_to?(:confidence_threshold)

          return Jevalyn.config.default_confidence_threshold
        end

        @confidence_threshold = validate_threshold!(value, "confidence_threshold")
      end

      # The floor one question is judged against: its own if it declared one, this
      # decision's default otherwise, and the global default under that.
      def confidence_threshold_for(name)
        declared = thresholds_by_question[name.to_sym]
        return declared unless declared.nil?

        confidence_threshold
      end

      # Every question's resolved floor, which is what a Result is judged against.
      def thresholds
        questions.keys.to_h { |name| [name, confidence_threshold_for(name)] }
      end

      # Per-question floors declared on this class and its ancestors.
      def thresholds_by_question
        inherited = superclass.respond_to?(:thresholds_by_question) ? superclass.thresholds_by_question : {}
        inherited.merge(own_thresholds)
      end

      # Pins this decision to a specific model. Worth doing once you have tuned
      # thresholds against a version -- `jev-latest` moves without telling you.
      def model(value = :__read__)
        if value == :__read__
          return @model if defined?(@model) && @model
          return superclass.model if superclass.respond_to?(:model)

          return nil
        end

        @model = value
      end

      # All questions, inherited ones first.
      def questions
        inherited = superclass.respond_to?(:questions) ? superclass.questions : {}
        inherited.merge(own_questions)
      end

      def question_names = questions.keys

      # Evaluates the state and returns a Jevalyn::Result with a reader per question.
      #
      # Two ways to override the declared floors for one call. `confidence_threshold:`
      # applies one number to every question; `thresholds:` names them individually and
      # wins over the blanket value where both are given.
      #
      #   SupportTriage.evaluate(body, confidence_threshold: 0.95)
      #   SupportTriage.evaluate(body, thresholds: { department: 0.9 })
      def evaluate(state, model: nil, confidence_threshold: :__default__, thresholds: nil,
                   client: Jevalyn.client)
        ensure_questions!

        client.evaluate(
          state: state,
          questions: questions,
          model: model || self.model,
          thresholds: resolve_thresholds(confidence_threshold, thresholds),
          result_class: result_class,
          decision: self
        )
      end

      # Same call, on an ActiveJob queue. The block runs with the Result once the job
      # completes; see Jevalyn::EvaluationJob for the handler contract.
      def evaluate_later(state, on:, model: nil, queue: nil, **job_options)
        ensure_questions!
        EvaluationJob.enqueue(
          decision: self, state: state, handler: on, model: model, queue: queue, **job_options
        )
      end

      # The request body that `evaluate` would send, without sending it. Handy in a
      # console for checking token cost before wiring a decision into a hot path.
      def payload_for(state, model: nil)
        {
          "model" => model || self.model || Jevalyn.config.default_model,
          "state" => State.serialize(state),
          "questions" => questions.each_with_object({}) { |(name, q), out| out[name.to_s] = q.to_payload }
        }
      end

      # Rough input-token estimate for a given state. The real number comes back in
      # Result#input_tokens; this is for sizing things up beforehand.
      def estimated_tokens(state)
        State.estimated_tokens(payload_for(state))
      end

      def result_class
        @result_class ||= build_result_class
      end

      # Overridden by Guardrail to bolt #allow? onto the result.
      def build_result_class
        Result.class_for(questions)
      end

      def own_questions
        @own_questions ||= {}
      end

      def own_thresholds
        @own_thresholds ||= {}
      end

      private

      def inherited(subclass)
        super
        subclass.instance_variable_set(:@own_questions, {})
        subclass.instance_variable_set(:@own_thresholds, {})
      end

      # Call-site overrides, least specific first: the declared floors, then a blanket
      # value applied to every question, then per-question values on top of that.
      def resolve_thresholds(blanket, per_question)
        resolved =
          if blanket == :__default__
            thresholds
          else
            validate_threshold!(blanket, "confidence_threshold")
            questions.keys.to_h { |name| [name, blanket] }
          end

        return resolved if per_question.nil?

        per_question.each_with_object(resolved.dup) do |(name, value), out|
          name = name.to_sym

          unless questions.key?(name)
            raise ConfigurationError,
                  "#{self.name || "This Decision"} declares no question named #{name.inspect}. " \
                  "It has: #{question_names.map(&:inspect).join(", ")}."
          end

          out[name] = validate_threshold!(value, name.inspect)
        end
      end

      def validate_threshold!(value, label)
        return value if value.nil? || (value.is_a?(Numeric) && value.between?(0, 1))

        raise ConfigurationError,
              "#{label} must be nil or a number between 0 and 1, got #{value.inspect}."
      end

      def ensure_questions!
        return unless questions.empty?

        raise ConfigurationError,
              "#{name || "This Decision"} declares no questions. Add at least one with " \
              "`question :name, type: :noul, instructions: \"...\"`."
      end

      def reset_result_class!
        @result_class = nil
      end
    end
  end
end
