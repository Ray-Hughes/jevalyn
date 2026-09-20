# frozen_string_literal: true

module Jevalyn
  # Runs a Decision on an ActiveJob queue.
  #
  # Jev answers in well under a second, so the default advice is to call `evaluate`
  # inline and keep the decision in the request's control flow -- that is the whole
  # point of a System One model. Reach for `evaluate_later` when the decision is not
  # on the critical path: backfilling triage over old tickets, scoring a batch
  # overnight, or anywhere a third-party outage must not take a request down with it.
  #
  #   SupportTriage.evaluate_later(ticket, on: TicketRouter)
  #   SupportTriage.evaluate_later(ticket, on: "TicketRouter.route")
  #
  # The handler is called with (result, state). It is named rather than passed as a
  # block because a block cannot be serialised onto a queue.
  module EvaluationJob
    class << self
      def enqueue(decision:, state:, handler:, model: nil, queue: nil, **options)
        ensure_active_job!

        job_class.set(queue: queue || Jevalyn.config.job_queue_name, **options).perform_later(
          decision.name,
          serializable(state),
          handler_name(handler),
          model
        )
      end

      def job_class
        @job_class ||= build_job_class
      end

      private

      def ensure_active_job!
        return if defined?(::ActiveJob::Base)

        raise ConfigurationError,
              "evaluate_later needs ActiveJob, which is not loaded. Use `evaluate` for " \
              "an inline call -- Jev answers fast enough to sit in a request."
      end

      # A Decision's state has to survive a round trip through the queue. GlobalID
      # handles ActiveRecord; everything else has to already be JSON-shaped.
      def serializable(state)
        return state if state.is_a?(String) || state.is_a?(Hash) || state.is_a?(Array)
        return state if defined?(::GlobalID) && state.respond_to?(:to_global_id)

        State.serialize(state)
      end

      def handler_name(handler)
        return handler if handler.is_a?(String)
        return handler.name if handler.is_a?(Class) || handler.is_a?(Module)

        raise ConfigurationError,
              "`on:` must be a class, module, or a \"ClassName.method\" string -- a job " \
              "handler has to survive serialisation, so it cannot be a block or a lambda."
      end

      def build_job_class
        klass = Class.new(::ActiveJob::Base) do
          def perform(decision_name, state, handler_name, model = nil)
            decision = Object.const_get(decision_name)
            result = decision.evaluate(state, model: model)

            target, method_name = handler_name.split(".", 2)
            Object.const_get(target).public_send(method_name || "call", result, state)
          end
        end

        # Named so backends that serialise by class name have something stable to use.
        Jevalyn.const_set(:Job, klass) unless Jevalyn.const_defined?(:Job)
        klass
      end
    end
  end
end
