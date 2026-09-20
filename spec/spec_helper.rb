# frozen_string_literal: true

require "jevalyn"
require "webmock/rspec"

require "jevalyn/testing/rspec"
require_relative "support/decisions"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before do
    Jevalyn.reset!
    Jevalyn.configure do |c|
      c.api_key = "test-key"
      c.mock_mode = false
      c.retry_backoff = 0
    end
  end
end

# Builds the body the API would return, so specs assert against a real response shape
# rather than one invented to suit the parser.
module ResponseFixtures
  module_function

  def systemone(answers, model: "jev-1.13.0", usage: { "input_tokens" => 312, "output_tokens" => 48 })
    { "model" => model, "answers" => answers, "usage" => usage }
  end

  def noul(value) = { "type" => "noul", "noul" => value }

  def choice(chosen, probabilities, confidence)
    { "type" => "choice", "choice" => chosen, "probabilities" => probabilities, "confidence" => confidence }
  end

  def score(value, legend, probabilities, confidence)
    { "type" => "score", "score" => value, "legend" => legend,
      "probabilities" => probabilities, "confidence" => confidence }
  end
end
