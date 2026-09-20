# frozen_string_literal: true

module Jevalyn
  # One typed answer from Jev, wrapped so callers read it as Ruby rather than as a
  # Hash of strings. Every answer knows the Question it came from, which is what lets
  # a Choice come back as a Symbol and a Score come back with its label attached.
  class Answer
    attr_reader :question, :raw

    def initialize(question, raw)
      @question = question
      @raw = raw || {}
    end

    def name = question.name

    def type = question.type

    # The API's own certainty statistic, 0..1. Choice and Score carry one; a Noul
    # does not, so this is nil for nouls. Use #certainty for a uniform number.
    def confidence
      value = raw["confidence"]
      value&.to_f
    end

    # A 0..1 "how sure is this" usable across all three question types.
    #
    # For Choice and Score this is the API's own `confidence`. Jev returns no
    # confidence for a Noul, so Jevalyn derives one from how far the probability sits
    # from the 0.5 coin-flip: 0.92 and 0.08 are both decisive, 0.5 is not. This is
    # Jevalyn's arithmetic, not TypeSafe's -- see Answer::Noul#decisiveness.
    def certainty = confidence

    # True when this answer clears the given confidence floor.
    def certain?(threshold)
      return true if threshold.nil?

      value = certainty
      return false if value.nil?

      value >= threshold
    end

    def uncertain?(threshold) = !certain?(threshold)

    # The full distribution the answer was derived from, keys left as the API sent them.
    def probabilities
      raw["probabilities"] || {}
    end

    def value = raise(NotImplementedError)

    def to_h = raw

    def inspect
      "#<#{self.class.name} #{name}=#{value.inspect} certainty=#{certainty.inspect}>"
    end

    # Probability that a yes/no question is a yes.
    class Noul < Answer
      # The raw 0..1 value. Deliberately not rounded to a boolean -- the whole point
      # of a noul is that you pick the cutoff your use case can afford.
      def value
        raw["noul"]&.to_f
      end
      alias noul value
      alias probability value

      # How far from a coin flip the answer sits, rescaled to 0..1.
      # 0.92 -> 0.84, 0.5 -> 0.0, 0.08 -> 0.84.
      def decisiveness
        return nil if value.nil?

        ((value - 0.5).abs * 2).round(10)
      end

      def certainty = decisiveness

      # Jev returns no confidence for a noul; this stays nil on purpose.
      def confidence = nil

      def true?(threshold = 0.5)
        return false if value.nil?

        value >= threshold
      end

      def false?(threshold = 0.5) = !true?(threshold)

      # A noul has no `probabilities` field; the value is the probability of yes.
      def probabilities
        return {} if value.nil?

        { "true" => value, "false" => (1.0 - value).round(10) }
      end
    end

    # One option out of the declared set.
    class Choice < Answer
      # The winning option, as a Symbol so it reads like the criteria keys you wrote.
      def value
        chosen = raw["choice"]
        chosen&.to_sym
      end
      alias choice value

      # The winning option as the API spelled it.
      def value_s = raw["choice"]

      def probability_of(option)
        probabilities[option.to_s]&.to_f
      end

      # Options ordered most to least likely.
      def ranked
        probabilities.sort_by { |_, probability| -probability.to_f }
                     .map { |option, probability| [option.to_sym, probability.to_f] }
      end

      def runner_up
        ranked[1]&.first
      end
    end

    # A rating against the declared levels.
    class Score < Answer
      # The probability-weighted score. A Float, and it lands between levels on
      # purpose -- 1.6 means "past Frustrated, not quite Very angry".
      def value
        raw["score"]&.to_f
      end
      alias score value

      # Level index mapped back to its description, as the API returned it.
      def legend
        raw["legend"] || {}
      end

      # The nearest whole level.
      def level
        return nil if value.nil?

        value.round
      end

      # The description of the nearest whole level, e.g. "Very angry".
      def label
        return nil if level.nil?

        legend[level.to_s] || question.levels[level]
      end

      # Highest-probability level, which is not always the nearest to #value.
      def modal_level
        top = probabilities.max_by { |_, probability| probability.to_f }
        top && Integer(top.first)
      rescue ArgumentError, TypeError
        nil
      end

      def probability_of(level_index)
        probabilities[level_index.to_s]&.to_f
      end

      # Score normalised to 0..1 across the declared levels, for weighting in code.
      def normalized
        return nil if value.nil?

        span = question.levels.length - 1
        return nil if span <= 0

        (value / span).round(10)
      end
    end
  end
end
