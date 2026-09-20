# frozen_string_literal: true

require "jevalyn/testing"

# RSpec integration. Add to spec/spec_helper.rb:
#
#   require "jevalyn/testing/rspec"
#
# It turns mock_mode on for the suite, clears stubs between examples, and adds:
#
#   stub_jevalyn(SupportTriage, department: :technical, urgent: true)
#   expect(SupportTriage).to have_been_evaluated
#   expect(result).to be_certain_above(0.8)
#
# Tag an example `:jevalyn_live` to let it reach the real API.
module Jevalyn
  module Testing
    module RSpecHelpers
      def stub_jevalyn(decision, **values, &)
        Jevalyn::Testing.stub(decision, **values, &)
      end

      def stub_any_jevalyn(**values, &)
        Jevalyn::Testing.stub_any(**values, &)
      end

      def forbid_jevalyn(decision)
        Jevalyn::Testing.forbid(decision)
      end

      def jevalyn_calls = Jevalyn::Testing.calls

      # The states passed to a decision, in call order.
      def jevalyn_states_for(decision)
        Jevalyn::Testing.calls.select { |call| call.decision == decision }.map(&:state)
      end

      def jevalyn_cassette(path, &)
        Jevalyn::Testing::Cassette.use(path, &)
      end
    end
  end
end

if defined?(RSpec)
  require "rspec/expectations"

  RSpec::Matchers.define :have_been_evaluated do
    match do |decision|
      @calls = Jevalyn::Testing.calls.select { |call| call.decision == decision }
      @calls = @calls.select { |call| values_match?(@with, call.state) } if defined?(@with)
      @count ? @calls.length == @count : @calls.any?
    end

    chain(:times) { |count| @count = count }
    chain(:once) { @count = 1 }
    chain(:with_state) { |state| @with = state }

    failure_message do |decision|
      seen = Jevalyn::Testing.calls.map { |call| call.decision.to_s }.tally
      "expected #{decision} to have been evaluated#{" #{@count} time(s)" if @count}, " \
        "but #{seen.empty? ? "nothing was evaluated" : "saw: #{seen.inspect}"}"
    end

    failure_message_when_negated do |decision|
      "expected #{decision} not to have been evaluated, but it was #{@calls.length} time(s)"
    end
  end

  RSpec::Matchers.define :be_certain_above do |threshold|
    match { |result| result.certain?(threshold) }

    failure_message do |result|
      "expected every answer to clear #{threshold}, but " \
        "#{result.uncertain_questions(threshold).map(&:inspect).join(", ")} did not " \
        "(lowest certainty #{result.min_certainty.inspect})"
    end
  end

  RSpec.configure do |config|
    config.include Jevalyn::Testing::RSpecHelpers

    config.around do |example|
      previous = Jevalyn.config.mock_mode
      Jevalyn.config.mock_mode = !example.metadata[:jevalyn_live]
      Jevalyn::Testing.reset!
      example.run
    ensure
      Jevalyn.config.mock_mode = previous
      Jevalyn::Testing.reset!
    end
  end
end
