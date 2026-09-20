# frozen_string_literal: true

module Jevalyn
  module StateAdapters
    # Serialises an ActiveRecord model into the `state` field.
    #
    # The default is `record.as_json`, which sends every column. That is usually the
    # wrong thing: it burns tokens on ids and timestamps Jev has no use for, and it
    # ships PII to a third party that did not need it. Narrow it with `only:`, or
    # define #jevalyn_state on the model and forget the adapter exists.
    class ActiveRecordAdapter
      # Columns that are noise in almost every decision.
      DEFAULT_EXCEPT = %w[id created_at updated_at].freeze

      def self.serialize(record, only: nil, except: nil)
        return record.jevalyn_state if only.nil? && except.nil? && record.respond_to?(:jevalyn_state)

        options = {}
        options[:only] = Array(only).map(&:to_s) if only
        options[:except] = Array(except).map(&:to_s) if except

        State.stringify(record.as_json(**options))
      end
    end
  end
end
