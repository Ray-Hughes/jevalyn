# frozen_string_literal: true

require "json"

module Jevalyn
  # Turns whatever you hand a Decision into something the API accepts as `state`:
  # a String, an Object or an Array.
  #
  # The convention is one method. If an object responds to #jevalyn_state, that is the
  # state -- which is how a model says "send these five columns, not all forty".
  # Otherwise Jevalyn falls back to #as_json, then to #to_s.
  module State
    # Jev's per-request budget: 64k tokens for state plus every question, and 32k for
    # state plus the single longest question. Tokens are not characters, so this is a
    # deliberately loose guard against posting a whole database row set by accident.
    ROUGH_CHARS_PER_TOKEN = 4
    SOFT_CHAR_LIMIT = 32_000 * ROUGH_CHARS_PER_TOKEN

    module_function

    def serialize(object)
      state = coerce(object)

      if state.nil? || (state.respond_to?(:empty?) && state.empty?)
        raise ConfigurationError,
              "State is empty. Jev needs something to evaluate -- pass a String, a Hash, " \
              "an Array, or an object that responds to #jevalyn_state."
      end

      state
    end

    def coerce(object)
      case object
      when nil            then nil
      when String         then object
      when Symbol         then object.to_s
      # Numbers and booleans are valid JSON and read better to the model as
      # themselves than as quoted strings.
      when Numeric, true, false then object
      when Hash           then stringify(object)
      when Array          then object.map { |item| coerce(item) }
      else
        coerce_object(object)
      end
    end

    # Rough token estimate, for logging and for the oversize warning. Not exact --
    # only the API knows the real count, and it reports it back in `usage`.
    def estimated_tokens(state)
      json = state.is_a?(String) ? state : JSON.generate(state)
      (json.length / ROUGH_CHARS_PER_TOKEN.to_f).ceil
    end

    def oversized?(state)
      json = state.is_a?(String) ? state : JSON.generate(state)
      json.length > SOFT_CHAR_LIMIT
    end

    def coerce_object(object)
      return coerce(object.jevalyn_state) if object.respond_to?(:jevalyn_state)

      if defined?(::ActiveRecord::Base) && object.is_a?(::ActiveRecord::Base)
        return StateAdapters::ActiveRecordAdapter.serialize(object)
      end

      if defined?(::ActiveRecord::Relation) && object.is_a?(::ActiveRecord::Relation)
        return object.map { |record| coerce(record) }
      end

      return coerce(object.as_json) if object.respond_to?(:as_json)

      object.to_s
    end

    def stringify(hash)
      hash.each_with_object({}) { |(key, value), out| out[key.to_s] = coerce(value) }
    end
  end
end
