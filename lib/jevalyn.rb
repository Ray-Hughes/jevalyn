# frozen_string_literal: true

require "jevalyn/version"
require "jevalyn/errors"
require "jevalyn/configuration"
require "jevalyn/question"
require "jevalyn/answer"
require "jevalyn/result"
require "jevalyn/state_adapters/active_record_adapter"
require "jevalyn/state"
require "jevalyn/testing"
require "jevalyn/testing/cassette"
require "jevalyn/client"
require "jevalyn/decision"
require "jevalyn/guardrail"
require "jevalyn/router"
require "jevalyn/evaluation_job"

require "jevalyn/railtie" if defined?(Rails::Railtie)

# Jevalyn is the decision layer for your Rails app.
#
# It wraps TypeSafe's Jev, a System One model: you give it a state and a set of typed
# questions, and it gives back typed, calibrated answers. A probability that something
# is true, one category out of a set you defined, a rating against your own rubric.
#
# That is the whole surface. Jev does not write prose, summarise, or reason
# open-endedly, and Jevalyn does not pretend otherwise. What it does is make a
# decision cheap enough and fast enough to sit directly in a Rails request.
#
#   class SupportTriage < Jevalyn::Decision
#     question :department, type: :choice,
#       instructions: "Which team should handle this?",
#       criteria: {
#         billing:   "Payments, invoicing, refunds",
#         technical: "Bugs, outages, integrations",
#         sales:     "Pricing, upgrades, new accounts"
#       }
#   end
#
#   SupportTriage.evaluate(ticket.body).department   # => :technical
module Jevalyn
  class << self
    def config
      @config ||= Configuration.new
    end

    # Set up in config/initializers/jevalyn.rb.
    #
    #   Jevalyn.configure do |c|
    #     c.api_key = ENV["TYPESAFE_API_KEY"]
    #   end
    def configure
      yield config
      reset_client!
      config
    end

    # The shared Client. Thread-safe to read; rebuilt whenever config changes.
    def client
      @client ||= Client.new(config)
    end

    def logger = config.logger

    # One-off evaluation without declaring a Decision class. Fine in a console or a
    # rake task; in application code a Decision gives you validation and a name.
    #
    #   Jevalyn.evaluate(
    #     "Help! My payouts have been failing for 3 days.",
    #     urgent: { type: :noul, instructions: "Does this convey urgency?" }
    #   )
    def evaluate(state, **questions)
      client.evaluate(state: state, questions: questions)
    end

    def reset_client!
      @client = nil
    end

    # Resets everything, for specs that mutate configuration.
    def reset!
      @config = nil
      @client = nil
      Testing.reset!
    end
  end
end
