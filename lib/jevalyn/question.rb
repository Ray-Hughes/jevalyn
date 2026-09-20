# frozen_string_literal: true

module Jevalyn
  # A single typed question. Jev has exactly three kinds and Jevalyn validates the
  # shape of each one when the Decision class is defined, so a malformed rubric is a
  # boot-time error rather than a 422 in production.
  class Question
    # Jev accepts up to 255 options on a Choice.
    MAX_CHOICE_OPTIONS = 255

    # A Score needs at least two levels and takes up to ten.
    MIN_SCORE_LEVELS = 2
    MAX_SCORE_LEVELS = 10

    TYPES = %i[noul choice score].freeze

    attr_reader :name, :instructions, :criteria

    def self.build(name, type:, instructions:, criteria: nil)
      klass = case type.to_sym
              when :noul   then Noul
              when :choice then Choice
              when :score  then Score
              else
                raise InvalidQuestionError,
                      "Unknown question type #{type.inspect} for :#{name}. " \
                      "Jev supports #{TYPES.map(&:inspect).join(", ")}."
              end

      klass.new(name, instructions: instructions, criteria: criteria)
    end

    def initialize(name, instructions:, criteria: nil)
      @name = name.to_sym
      @instructions = instructions
      @criteria = criteria
      validate!
      freeze
    end

    def type = self.class::TYPE

    # The JSON body for this question, as the API wants it.
    def to_payload
      payload = { "type" => type.to_s, "instructions" => instructions }
      payload["criteria"] = criteria_payload unless criteria_payload.nil?
      payload
    end

    # Wraps the raw answer hash the API returned for this question.
    def build_answer(raw)
      answer_class.new(self, raw)
    end

    private

    def criteria_payload = criteria

    def validate!
      validate_instructions!
      validate_criteria!
    end

    # The API accepts a string, object or array here -- anything JSON-shaped that
    # reads as an instruction. What it does not accept is nothing.
    def validate_instructions!
      return if instructions.is_a?(String) && !instructions.strip.empty?
      return if instructions.is_a?(Hash) && !instructions.empty?
      return if instructions.is_a?(Array) && !instructions.empty?

      raise InvalidQuestionError,
            "Question :#{name} needs non-empty :instructions (a String, Hash or Array), " \
            "got #{instructions.inspect}."
    end

    def validate_criteria!
      raise NotImplementedError
    end

    # Probability that the answer to a yes/no question is yes.
    class Noul < Question
      TYPE = :noul

      def answer_class = Answer::Noul

      private

      # Optional. When given it explains what a yes and a no mean.
      def validate_criteria!
        return if criteria.nil?

        unless criteria.is_a?(Hash)
          raise InvalidQuestionError,
                "Question :#{name} is a :noul, so :criteria must be a Hash with " \
                ":true and/or :false keys, got #{criteria.class}."
        end

        unknown = criteria.keys.map(&:to_s) - %w[true false]
        return if unknown.empty?

        raise InvalidQuestionError,
              "Question :#{name} is a :noul, so :criteria accepts only :true and :false. " \
              "Unknown key(s): #{unknown.join(", ")}."
      end

      def criteria_payload
        return nil if criteria.nil?

        criteria.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end
    end

    # One option out of a labelled set.
    class Choice < Question
      TYPE = :choice

      def answer_class = Answer::Choice

      # The option keys, in declaration order.
      def options = criteria.keys.map(&:to_sym)

      private

      def validate_criteria!
        unless criteria.is_a?(Hash) && !criteria.empty?
          raise InvalidQuestionError,
                "Question :#{name} is a :choice, so :criteria must be a non-empty Hash of " \
                "option => description, got #{criteria.inspect}."
        end

        if criteria.size > MAX_CHOICE_OPTIONS
          raise InvalidQuestionError,
                "Question :#{name} declares #{criteria.size} options; Jev accepts at most " \
                "#{MAX_CHOICE_OPTIONS}."
        end

        bad = criteria.reject { |_, value| value.nil? || value.is_a?(String) }
        return if bad.empty?

        raise InvalidQuestionError,
              "Question :#{name} has non-String descriptions for option(s) " \
              "#{bad.keys.join(", ")}. Use a String, or nil when the option needs no detail."
      end

      def criteria_payload
        criteria.each_with_object({}) { |(key, value), out| out[key.to_s] = value }
      end
    end

    # A rating against ordered levels.
    class Score < Question
      TYPE = :score

      def answer_class = Answer::Score

      # The level descriptions, lowest first.
      def levels = criteria.map(&:to_s)

      private

      def validate_criteria!
        unless criteria.is_a?(Array)
          raise InvalidQuestionError,
                "Question :#{name} is a :score, so :criteria must be an ordered Array of " \
                "level descriptions, got #{criteria.class}."
        end

        unless criteria.size.between?(MIN_SCORE_LEVELS, MAX_SCORE_LEVELS)
          raise InvalidQuestionError,
                "Question :#{name} declares #{criteria.size} level(s); a Jev score takes " \
                "between #{MIN_SCORE_LEVELS} and #{MAX_SCORE_LEVELS}."
        end

        bad = criteria.reject { |level| level.is_a?(String) || level.is_a?(Symbol) }
        return if bad.empty?

        raise InvalidQuestionError,
              "Question :#{name} has non-String level(s): #{bad.map(&:inspect).join(", ")}."
      end

      def criteria_payload = levels
    end
  end
end
