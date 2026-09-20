# frozen_string_literal: true

module Jevalyn
  # Process-wide settings. Set these once in config/initializers/jevalyn.rb.
  class Configuration
    DEFAULT_BASE_URL = "https://api.typesafe.ai"
    DEFAULT_MODEL    = "jev-latest"

    # The official SDKs default to 10s. Jev answers in well under a second, so a
    # long timeout only means a slow request holds a Rails thread open.
    DEFAULT_TIMEOUT      = 10.0
    DEFAULT_OPEN_TIMEOUT = 5.0

    # 429 and 529 are expected under load; the API asks us to back off, not give up.
    DEFAULT_MAX_RETRIES   = 2
    DEFAULT_RETRY_BACKOFF = 0.5

    # Bearer token for the TypeSafe API.
    attr_accessor :api_key

    # Override to point at a proxy or a recorded fixture server.
    attr_accessor :base_url

    # Model name or alias sent when a call does not name one.
    attr_accessor :default_model

    # Per-request read timeout, in seconds.
    attr_accessor :timeout

    # Connection-open timeout, in seconds.
    attr_accessor :open_timeout

    # When true, no HTTP request is ever made -- answers come from Jevalyn::Testing.
    attr_accessor :mock_mode

    # How many times a retryable response (429 / 529 / 5xx) is retried.
    attr_accessor :max_retries

    # Base delay for exponential backoff between retries, in seconds.
    attr_accessor :retry_backoff

    # Anything responding to #info / #warn / #debug. Defaults to the Rails logger.
    attr_accessor :logger

    # Confidence floor a Decision uses when it does not declare its own.
    attr_accessor :default_confidence_threshold

    # ActiveJob queue used by .evaluate_later.
    attr_accessor :job_queue_name

    def initialize
      @api_key       = ENV.fetch("TYPESAFE_API_KEY", nil)
      @base_url      = ENV.fetch("TYPESAFE_BASE_URL", DEFAULT_BASE_URL)
      @default_model = ENV.fetch("TYPESAFE_DEFAULT_MODEL", DEFAULT_MODEL)
      @timeout       = DEFAULT_TIMEOUT
      @open_timeout  = DEFAULT_OPEN_TIMEOUT
      @mock_mode     = false
      @max_retries   = DEFAULT_MAX_RETRIES
      @retry_backoff = DEFAULT_RETRY_BACKOFF
      @logger        = nil
      @default_confidence_threshold = nil
      @job_queue_name = :default
    end

    # Raises rather than letting a nil key turn into a confusing 401.
    def api_key!
      return @api_key if @api_key && !@api_key.to_s.strip.empty?

      raise ConfigurationError, <<~MSG.strip
        No TypeSafe API key configured. Set TYPESAFE_API_KEY in the environment, or
        assign one in config/initializers/jevalyn.rb:

          Jevalyn.configure do |c|
            c.api_key = ENV["TYPESAFE_API_KEY"]
          end

        In tests, set `c.mock_mode = true` instead and stub with Jevalyn::Testing.
      MSG
    end

    def evaluation_url = "#{base_url.to_s.chomp("/")}/v1/systemone"

    def models_url = "#{base_url.to_s.chomp("/")}/v1/models"
  end
end
