# frozen_string_literal: true

module Jevalyn
  # A Decision narrowed to one job: should this be allowed through?
  #
  #   class ToolCallGuardrail < Jevalyn::Guardrail
  #     question :safe_to_execute, type: :noul,
  #       instructions: "Is this tool call safe to run without human review?"
  #
  #     allow_above 0.9
  #   end
  #
  #   ToolCallGuardrail.check(tool_call).allow?   # => false
  #
  # A guardrail declares exactly one noul question. Jev returns no confidence for a
  # noul -- the probability *is* the answer -- so the gate is the probability itself,
  # and `allow_above` is where you set it. The default is 0.5, which is a coin flip
  # and almost certainly not what you want in front of anything destructive.
  class Guardrail < Decision
    DEFAULT_ALLOW_ABOVE = 0.5

    # A guardrail that fails open is worse than one that fails loudly, so an error
    # from the API denies rather than allows.
    DEFAULT_ON_ERROR = :deny

    class << self
      # Probability the noul must reach for #allow? to be true.
      def allow_above(value = :__read__)
        if value == :__read__
          return @allow_above if defined?(@allow_above) && @allow_above
          return superclass.allow_above if superclass.respond_to?(:allow_above)

          return DEFAULT_ALLOW_ABOVE
        end

        unless value.is_a?(Numeric) && value.between?(0, 1)
          raise ConfigurationError,
                "allow_above must be a number between 0 and 1, got #{value.inspect}."
        end

        @allow_above = value
      end

      # What to do when the API call itself fails: :deny (default) or :raise.
      def on_error(value = :__read__)
        if value == :__read__
          return @on_error if defined?(@on_error) && @on_error
          return superclass.on_error if superclass.respond_to?(:on_error)

          return DEFAULT_ON_ERROR
        end

        unless %i[deny raise].include?(value)
          raise ConfigurationError, "on_error must be :deny or :raise, got #{value.inspect}."
        end

        @on_error = value
      end

      # Runs the guardrail. Returns a Result answering #allow? and #deny?.
      def check(state, **options)
        evaluate(state, **options)
      rescue APIError, TimeoutError, ConnectionError => e
        raise if on_error == :raise

        Jevalyn.logger&.warn("[jevalyn] #{name} denied by default: #{e.class}: #{e.message}")
        denied_result(e)
      end

      def evaluate(...)
        ensure_single_noul!
        super
      end

      def build_result_class
        decision = self

        Class.new(super) do
          # The gate is read at call time so `allow_above` can be changed after the
          # class body has run -- in an initializer, or per environment.
          define_method(:threshold) { decision.allow_above }

          # The raw probability the gate is compared against.
          define_method(:probability) { answer(decision.question_names.first).value }

          def allow?
            value = probability
            !value.nil? && value >= threshold
          end

          def deny? = !allow?

          # Set when the guardrail denied because the call failed, not because Jev said no.
          attr_reader :error

          def failed? = !error.nil?
        end
      end

      private

      # A denial the caller can treat like any other, carrying the cause.
      def denied_result(error)
        question_key = question_names.first.to_s
        raw = { "answers" => { question_key => { "type" => "noul", "noul" => 0.0 } } }

        result = result_class.new(questions: questions, raw: raw, thresholds: thresholds)
        result.instance_variable_set(:@error, error)
        result
      end

      def ensure_single_noul!
        declared = questions.values

        if declared.size != 1
          raise ConfigurationError,
                "#{name || "A Guardrail"} must declare exactly one question, found " \
                "#{declared.size}. Use a Jevalyn::Decision when you need more than one."
        end

        return if declared.first.type == :noul

        raise ConfigurationError,
              "#{name || "A Guardrail"} question :#{declared.first.name} is a " \
              ":#{declared.first.type}. A guardrail asks one yes/no question, so it " \
              "must be a :noul."
      end
    end
  end
end
