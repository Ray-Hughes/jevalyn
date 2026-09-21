# frozen_string_literal: true

module Jevalyn
  # Sends work to a handler based on a decision, with a confidence floor underneath.
  #
  # Two shapes, and they compose. A plain dispatch table:
  #
  #   router = Jevalyn::Router.new do |r|
  #     r.route :simple_lookup, to: OrderLookup
  #     r.route :open_ended,    to: llm_client   # anything responding to #call
  #   end
  #
  #   router.dispatch(:simple_lookup, state: order)
  #
  # Or a decision-driven router, which is the reason this class exists -- Jev picks
  # the branch, and anything it is not sure about goes somewhere safer:
  #
  #   router = Jevalyn::Router.new(SupportTriage, on: :department) do |r|
  #     r.route :billing,   to: BillingInbox
  #     r.route :technical, to: ->(state, result) { Oncall.page(state, result) }
  #     r.route :sales,     to: SalesInbox
  #     r.uncertain_below to: HumanQueue
  #   end
  #
  #   router.call(ticket)
  #
  # Handlers are called with (state, result) when they take two arguments and (state)
  # when they take one, so a plain Proc, a Decision, a job class and a service object
  # all work without adapters.
  class Router
    Route = Struct.new(:key, :handler, keyword_init: true)

    attr_reader :decision, :question, :routes

    # decision -- optional Jevalyn::Decision subclass that picks the branch.
    # on       -- the choice question whose answer names the route. Defaults to the
    #             decision's only question when it declares just one.
    def initialize(decision = nil, on: nil)
      @decision = decision
      @question = on
      @routes = {}
      @fallback = nil
      @floor = nil
      @floor_handler = nil

      yield self if block_given?

      validate_question! if decision
    end

    # Registers a handler under a key.
    def route(key, to:)
      @routes[key.to_sym] = Route.new(key: key.to_sym, handler: to)
      self
    end

    # Where anything unrouted goes. Without one, an unrouted key raises.
    def fallback(to:)
      @fallback = to
      self
    end

    # Where an answer that misses its confidence floor goes, whatever the answer was.
    # This is the confidence-gated half: a wrong-but-confident answer is a routing bug,
    # a not-confident answer is a known unknown and belongs with a human or a slower
    # model.
    #
    # With no threshold it uses the floor the question itself declares, so the number
    # lives in one place:
    #
    #   r.uncertain_below to: HumanQueue          # the decision's own floor
    #   r.uncertain_below 0.9, to: HumanQueue     # stricter, just for this router
    def uncertain_below(threshold = nil, to:)
      @floor = threshold
      @floor_handler = to
      self
    end

    # Calls a registered handler directly, skipping the decision.
    def dispatch(key, state:, result: nil)
      registered = @routes[key.to_sym]

      unless registered
        return invoke(@fallback, state, result) if @fallback

        raise UnknownQuestionError,
              "No route for #{key.inspect}. Registered: #{@routes.keys.map(&:inspect).join(", ")}."
      end

      invoke(registered.handler, state, result)
    end

    # Runs the decision, then dispatches on its answer.
    def call(state, **options)
      unless decision
        raise ConfigurationError,
              "This Router has no decision, so it can only #dispatch(key, state:). " \
              "Build it as Router.new(SomeDecision, on: :question) to use #call."
      end

      result = decision.evaluate(state, **options)
      answer = result.answer(question_name)

      floor = @floor || result.threshold_for(question_name)
      return invoke(@floor_handler, state, result) if @floor_handler && answer.uncertain?(floor)

      dispatch(answer.value, state: state, result: result)
    end

    # The decision's answer without dispatching -- useful in specs and consoles.
    def decide(state, **options)
      decision.evaluate(state, **options)
    end

    def keys = @routes.keys

    private

    def question_name
      @question || decision.question_names.first
    end

    def validate_question!
      name = question_name

      unless decision.questions.key?(name)
        raise ConfigurationError,
              "#{decision.name} declares no question named #{name.inspect}. " \
              "It has: #{decision.question_names.map(&:inspect).join(", ")}."
      end

      declared = decision.questions[name]

      unless declared.type == :choice
        raise ConfigurationError,
              "Router routes on a :choice question; #{decision.name}##{name} is a " \
              ":#{declared.type}."
      end

      unrouted = declared.options - @routes.keys
      return if unrouted.empty? || @fallback || @floor_handler

      raise ConfigurationError,
            "#{decision.name}##{name} can answer #{unrouted.map(&:inspect).join(", ")}, " \
            "which this Router has no route for. Add them, or a `fallback to:`."
    end

    # Handlers vary in shape on purpose: a Decision subclass, a Proc that only wants
    # the state, and a service object that wants both should all work unadapted.
    def invoke(handler, state, result)
      return handler.evaluate(state) if handler.is_a?(Class) && handler <= Decision

      unless handler.respond_to?(:call)
        raise ConfigurationError,
              "Route handler #{handler.inspect} must respond to #call, or be a " \
              "Jevalyn::Decision subclass."
      end

      return handler.call(state, result) if accepts_two?(handler)

      handler.call(state)
    end

    def accepts_two?(handler)
      method = handler.respond_to?(:parameters) ? handler : handler.method(:call)
      parameters = method.parameters

      return true if parameters.any? { |type, _| type == :rest }

      parameters.count { |type, _| %i[req opt].include?(type) } >= 2
    rescue NameError
      false
    end
  end
end
