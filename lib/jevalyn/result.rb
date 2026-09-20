# frozen_string_literal: true

module Jevalyn
  # Everything one evaluation returned: the typed answers, which model answered, and
  # what it cost. A Result is read-only and safe to pass around or serialise into a job.
  class Result
    # What a client sends in the `usage` position when nothing came back.
    EMPTY_USAGE = { "input_tokens" => 0, "output_tokens" => 0 }.freeze

    attr_reader :answers, :raw, :questions, :confidence_threshold

    # questions -- Hash of name => Question, in declaration order.
    # raw       -- the parsed response body, untouched.
    def initialize(questions:, raw:, confidence_threshold: nil)
      @questions = questions
      @raw = raw || {}
      @confidence_threshold = confidence_threshold
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

    # True when every answer clears the threshold. Nouls are judged on how far they
    # sit from a coin flip, since Jev returns no confidence for them.
    def certain?(threshold = confidence_threshold)
      uncertain_questions(threshold).empty?
    end

    def uncertain?(threshold = confidence_threshold) = !certain?(threshold)

    # Names of the answers that fell below the threshold -- the ones worth routing to
    # a human or a slower model.
    def uncertain_questions(threshold = confidence_threshold)
      return [] if threshold.nil?

      @answers.select { |_, answer| answer.uncertain?(threshold) }.keys
    end

    # The least certain answer's certainty, which is what `certain?` effectively gates on.
    def min_certainty
      certainties = @answers.values.filter_map(&:certainty)
      certainties.min
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

    def build_answers
      raw_answers = raw["answers"] || {}

      questions.each_with_object({}) do |(name, question), out|
        out[name] = question.build_answer(raw_answers[name.to_s])
      end.freeze
    end
  end
end
