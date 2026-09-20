# frozen_string_literal: true

require "jevalyn/testing"

# Minitest integration. In test_helper.rb:
#
#   require "jevalyn/testing/minitest"
#
#   class ActiveSupport::TestCase
#     include Jevalyn::Testing::Minitest
#   end
module Jevalyn
  module Testing
    module Minitest
      def self.included(base)
        base.setup do
          @jevalyn_previous_mock_mode = Jevalyn.config.mock_mode
          Jevalyn.config.mock_mode = true
          Jevalyn::Testing.reset!
        end

        base.teardown do
          Jevalyn.config.mock_mode = @jevalyn_previous_mock_mode
          Jevalyn::Testing.reset!
        end
      end

      def stub_jevalyn(decision, **values, &)
        Jevalyn::Testing.stub(decision, **values, &)
      end

      def assert_evaluated(decision, times: nil)
        calls = Jevalyn::Testing.calls.select { |call| call.decision == decision }

        if times
          assert_equal times, calls.length,
                       "expected #{decision} to be evaluated #{times} time(s), got #{calls.length}"
        else
          refute_empty calls, "expected #{decision} to have been evaluated"
        end
      end

      def refute_evaluated(decision)
        calls = Jevalyn::Testing.calls.select { |call| call.decision == decision }
        assert_empty calls, "expected #{decision} not to have been evaluated"
      end

      def assert_certain(result, threshold)
        assert result.certain?(threshold),
               "expected every answer to clear #{threshold}, but " \
               "#{result.uncertain_questions(threshold).inspect} did not"
      end
    end
  end
end
