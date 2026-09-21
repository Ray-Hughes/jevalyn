# frozen_string_literal: true

require "faraday"
require "json"

module Jevalyn
  # Thin, honest wrapper over POST /v1/systemone. It mirrors the HTTP API one-to-one:
  # a state, a map of questions, one answer per question. Everything ergonomic lives
  # a layer up in Decision -- this class stays boring on purpose.
  class Client
    USER_AGENT = "jevalyn/#{Jevalyn::VERSION} (ruby/#{RUBY_VERSION})".freeze

    # Statuses worth trying again after a backoff. 429 and 529 are the API's own
    # "slow down" and "come back later"; the rest are transient server faults.
    RETRYABLE_STATUSES = [429, 500, 502, 503, 504, 529].freeze

    attr_reader :config

    def initialize(config = Jevalyn.config)
      @config = config
    end

    # Evaluates a state against a map of questions.
    #
    # state     -- String, Hash or Array. Anything responding to #jevalyn_state or
    #              #as_json is serialised first; see Jevalyn::State.
    # questions -- Hash of name => Jevalyn::Question, or name => Hash payload.
    #
    # thresholds is Jevalyn's own, never sent: a Hash of question => confidence floor,
    # or a single number for all of them.
    #
    # Returns a Jevalyn::Result.
    def evaluate(state:, questions:, model: nil, confidence_threshold: nil, thresholds: nil,
                 result_class: Result, decision: nil)
      questions = normalize_questions(questions)
      body = {
        "model" => model || config.default_model,
        "state" => State.serialize(state),
        "questions" => questions.each_with_object({}) { |(name, q), out| out[name.to_s] = q.to_payload }
      }

      raw = if config.mock_mode
              Testing.answer(body: body, questions: questions, decision: decision)
            else
              Testing.through_cassette(body) { post(config.evaluation_url, body) }
            end

      result_class.new(questions: questions, raw: raw, thresholds: thresholds || confidence_threshold)
    end

    # GET /v1/models -- the names this account may send in the `model` field.
    def models
      return Testing.models if config.mock_mode

      get(config.models_url).fetch("models", [])
    end

    # Cheap liveness check for `rails runner` or a health endpoint.
    def reachable?
      models
      true
    end

    private

    def normalize_questions(questions)
      unless questions.is_a?(Hash) && !questions.empty?
        raise ConfigurationError,
              "evaluate needs a non-empty Hash of questions, got #{questions.inspect}."
      end

      questions.each_with_object({}) do |(name, question), out|
        out[name.to_sym] =
          case question
          when Question then question
          when Hash     then Question.build(name, **symbolize(question))
          else
            raise ConfigurationError,
                  "Question #{name.inspect} must be a Jevalyn::Question or a Hash, " \
                  "got #{question.class}."
          end
      end
    end

    def symbolize(hash)
      hash.each_with_object({}) { |(key, value), out| out[key.to_sym] = value }
    end

    def post(url, body)
      request(:post, url) { |req| req.body = JSON.generate(body) }
    end

    def get(url)
      request(:get, url)
    end

    def request(verb, url, &)
      attempt = 0

      begin
        response = connection.public_send(verb, url, &)
        handle(response)
      rescue Faraday::TimeoutError => e
        raise TimeoutError, timeout_message(e)
      rescue Faraday::ConnectionFailed, Faraday::SSLError => e
        # Faraday reports an open timeout as a connection failure. From the caller's
        # side it is still a timeout, and the difference matters when deciding whether
        # to retry, so unwrap it rather than passing the label along.
        raise TimeoutError, timeout_message(e) if timeout?(e)

        raise ConnectionError, "Could not reach #{config.base_url}: #{e.message}"
      rescue APIError => e
        attempt += 1
        raise unless e.retryable? && attempt <= config.max_retries.to_i

        sleep(backoff_for(attempt, e))
        retry
      end
    end

    def timeout?(error)
      wrapped = error.respond_to?(:wrapped_exception) ? error.wrapped_exception : nil

      wrapped.is_a?(Timeout::Error) || error.message.to_s.match?(/timed? ?out|execution expired/i)
    end

    def timeout_message(error)
      "TypeSafe request timed out after #{config.timeout}s (#{error.message})"
    end

    def handle(response)
      body = parse(response.body)
      return body if response.success?

      raise APIError.from_response(status: response.status, body: body, headers: response.headers)
    end

    def parse(body)
      return {} if body.nil? || body.to_s.strip.empty?
      return body if body.is_a?(Hash) || body.is_a?(Array)

      JSON.parse(body)
    rescue JSON::ParserError
      body.to_s
    end

    # Honour the API's own retry-after when it sends one, exponential backoff otherwise.
    def backoff_for(attempt, error)
      requested = error.respond_to?(:retry_after) ? error.retry_after : nil
      return requested if requested&.positive?

      config.retry_backoff.to_f * (2**(attempt - 1))
    end

    def connection
      @connection ||= Faraday.new do |f|
        f.headers["Authorization"] = "Bearer #{config.api_key!}"
        f.headers["Content-Type"]  = "application/json"
        f.headers["Accept"]        = "application/json"
        f.headers["User-Agent"]    = USER_AGENT
        f.options.timeout      = config.timeout
        f.options.open_timeout = config.open_timeout
        f.adapter Faraday.default_adapter
      end
    end
  end
end
