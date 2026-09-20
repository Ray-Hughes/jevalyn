# frozen_string_literal: true

module Jevalyn
  # Base class for everything Jevalyn raises.
  class Error < StandardError; end

  # Raised when the gem is asked to do something it has not been configured for
  # (missing API key, unknown question type, a Decision that declares no questions).
  class ConfigurationError < Error; end

  # Raised at class-definition time when a Decision declares a malformed question.
  class InvalidQuestionError < ConfigurationError; end

  # Raised when a Result is asked for a question that was never declared.
  class UnknownQuestionError < Error; end

  # The request never completed.
  class TimeoutError < Error; end

  # The request could not reach the API at all (DNS, TLS, refused connection).
  class ConnectionError < Error; end

  # The API answered with a non-2xx status.
  class APIError < Error
    attr_reader :status, :body, :response_headers

    def initialize(message = nil, status: nil, body: nil, response_headers: nil)
      @status = status
      @body = body
      @response_headers = response_headers || {}
      super(message || default_message)
    end

    # Builds the most specific error class for a given HTTP status.
    def self.from_response(status:, body:, headers: {})
      klass = case status
              when 401 then AuthenticationError
              when 403 then PermissionDeniedError
              when 404 then NotFoundError
              when 422 then InvalidRequestError
              when 429 then RateLimitError
              when 529 then OverloadedError
              when 500..599 then ServerError
              else self
              end

      klass.new(extract_message(body), status: status, body: body, response_headers: headers)
    end

    def self.extract_message(body)
      return body if body.is_a?(String)
      return nil unless body.is_a?(Hash)

      error = body["error"]
      return error if error.is_a?(String)
      return error["message"] if error.is_a?(Hash) && error["message"]

      body["message"] || body["detail"]
    end

    # True when retrying the identical request has a reasonable chance of succeeding.
    def retryable?
      false
    end

    private

    def default_message = "TypeSafe API returned HTTP #{status}"
  end

  # 401 -- missing or invalid API key.
  class AuthenticationError < APIError
    private

    def default_message
      "TypeSafe rejected the API key. Check Jevalyn.config.api_key / ENV[\"TYPESAFE_API_KEY\"]."
    end
  end

  # 403 -- the key is valid but not allowed to do this.
  class PermissionDeniedError < APIError; end

  # 404 -- unknown endpoint or model.
  class NotFoundError < APIError; end

  # 422 -- the request body failed validation. The body names the offending field.
  class InvalidRequestError < APIError
    private

    def default_message = "TypeSafe rejected the request body (HTTP 422)"
  end

  # 429 -- over the account's tokens-per-second or requests-per-minute limit.
  class RateLimitError < APIError
    def retryable? = true

    # Seconds the API asked us to wait, when it said.
    def retry_after
      value = response_headers["retry-after"] || response_headers["Retry-After"]
      Float(value)
    rescue ArgumentError, TypeError
      nil
    end

    private

    def default_message = "TypeSafe rate limit exceeded (HTTP 429)"
  end

  # 529 -- TypeSafe is temporarily overloaded.
  class OverloadedError < APIError
    def retryable? = true

    private

    def default_message = "TypeSafe is overloaded (HTTP 529)"
  end

  # 5xx other than 529.
  class ServerError < APIError
    def retryable? = true
  end
end
