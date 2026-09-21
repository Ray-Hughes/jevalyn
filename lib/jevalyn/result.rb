# frozen_string_literal: true

module Jevalyn
  # Everything one evaluation returned: the typed answers, which model answered, and
  # what it cost. A Result is read-only and safe to pass around or serialise into a job.
  class Result
    # What a client sends in the `usage` position when nothing came back.
    EMPTY_USAGE = { "input_tokens" => 0, "output_tokens" => 0 }.freeze

    attr_reader :answers, :raw, :questions

    # questions  -- Hash of name => Question, in declaration order.
    # raw        -- the parsed response body, untouched.
    # thresholds -- Hash of name => confidence floor, already resolved by the Decision.
    #               A nil floor means that question was not asked to clear anything.
    def initialize(questions:, raw:, thresholds: nil)
      @questions = questions
      @raw = raw || {}
      @thresholds = normalize_thresholds(thresholds)
      @answers = build_answers
    end

    # The versioned model that actually answered, e.g. "jev-1.13.0". Worth logging:
    # an alias like jev-latest moves under you, and this is what tells you when it did.
    def model = raw["model"]

    def usage = raw["usage"] || EMPTY_USAGE

    def input_tokens = usage["input_tokens"].to_i

    # Free, as of jev-1.13 -- TypeSafe bills on input tokens only.
    def output_tokens = usage["output_tokens"].to_i

    def [](name)
      answer(name).value
    end

    # The Answer object for a question, rather than its value.
    def answer(name)
      @answers.fetch(name.to_sym) do
        raise UnknownQuestionError,
              "No answer named #{name.inspect}. This result has: " \
              "#{@answers.keys.map(&:inspect).join(", ")}."
      end
    end

    def key?(name) = @answers.key?(name.to_sym)

    # Plain Hash of question name => unwrapped value.
    def values
      @answers.transform_values(&:value)
    end
    alias to_h values

    # The floor each question is judged against. Read it to see what a Decision
    # actually resolved, which is worth logging alongside the answers.
    attr_reader :thresholds

    def threshold_for(name)
      @thresholds[name.to_sym]
    end

    # True when every answer clears its own floor. Pass a number to judge them all
    # against that one instead. Nouls are measured on how far they sit from a coin
    # flip, since Jev returns no confidence for them.
    def certain?(threshold = nil)
      uncertain_questions(threshold).empty?
    end

    def uncertain?(threshold = nil) = !certain?(threshold)

    # True when one named answer clears its floor.
    def certain_for?(name, threshold = :__declared__)
      threshold = threshold_for(name) if threshold == :__declared__

      answer(name).certain?(threshold)
    end

    # Names of the answers that fell below their floor -- the ones worth routing to
    # a human or a slower model.
    def uncertain_questions(threshold = nil)
      @answers.reject do |name, answer|
        answer.certain?(threshold || @thresholds[name])
      end.keys
    end

    # The least certain answer's certainty, across every question.
    def min_certainty
      @answers.values.filter_map(&:certainty).min
    end

    # How far each answer sits above (or below) its own floor. Negative means it
    # missed. Useful for logging which decisions are running close to the line.
    def certainty_margins
      @answers.each_with_object({}) do |(name, answer), out|
        floor = @thresholds[name]
        certainty = answer.certainty
        out[name] = floor.nil? || certainty.nil? ? nil : (certainty - floor).round(10)
      end
    end

    def each(&) = @answers.each(&)

    include Enumerable

    def inspect
      pairs = values.map { |name, value| "#{name}=#{value.inspect}" }.join(" ")
      "#<#{self.class.name.nil? ? "Jevalyn::Result" : self.class.name} #{pairs} model=#{model.inspect}>"
    end

    # Builds a Result subclass with a reader per question, so a Decision's answers
    # read as `result.department` rather than `result[:department]`.
    def self.class_for(questions)
      Class.new(self) do
        questions.each_value do |question|
          name = question.name

          define_method(name) { self[name] }
          define_method(:"#{name}_answer") { answer(name) }
          define_method(:"#{name}_certainty") { answer(name).certainty }
          define_method(:"#{name}_probabilities") { answer(name).probabilities }
          define_method(:"#{name}_threshold") { threshold_for(name) }
          define_method(:"#{name}_certain?") { |threshold = :__declared__| certain_for?(name, threshold) }
          define_method(:"#{name}_uncertain?") { |threshold = :__declared__| !certain_for?(name, threshold) }

          case question.type
          when :noul
            define_method(:"#{name}?") { |threshold = 0.5| answer(name).true?(threshold) }
          when :choice
            define_method(:"#{name}_confidence") { answer(name).confidence }
          when :score
            define_method(:"#{name}_confidence") { answer(name).confidence }
            define_method(:"#{name}_label") { answer(name).label }
            define_method(:"#{name}_level") { answer(name).level }
          end
        end
      end
    end

    private

    # Accepts a Hash of floors, a single number meaning "all of them", or nothing.
    def normalize_thresholds(thresholds)
      case thresholds
      when nil     then questions.keys.to_h { |name| [name, nil] }.freeze
      when Numeric then questions.keys.to_h { |name| [name, thresholds] }.freeze
      when Hash
        questions.keys.to_h { |name| [name, thresholds[name] || thresholds[name.to_s]] }.freeze
      else
        raise ConfigurationError,
              "thresholds must be a Hash of question => floor, a single number, or nil; " \
              "got #{thresholds.class}."
      end
    end

    def build_answers
      raw_answers = raw["answers"] || {}

      questions.each_with_object({}) do |(name, question), out|
        out[name] = question.build_answer(raw_answers[name.to_s])
      end.freeze
    end
  end
end
