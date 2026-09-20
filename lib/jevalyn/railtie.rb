# frozen_string_literal: true

require "rails/railtie"

module Jevalyn
  # Wires Jevalyn into a Rails app: the generators, a sensible logger, and
  # app/decisions as an autoload path so decision classes live next to models.
  class Railtie < ::Rails::Railtie
    config.jevalyn = ActiveSupport::OrderedOptions.new if defined?(ActiveSupport::OrderedOptions)

    generators do
      require "generators/jevalyn/install/install_generator"
      require "generators/jevalyn/decision/decision_generator"
      require "generators/jevalyn/guardrail/guardrail_generator"
    end

    initializer "jevalyn.logger" do
      Jevalyn.config.logger ||= Rails.logger
    end

    # A Rails app almost never wants a real API call in its test suite, and a key is
    # usually absent there anyway. Opt back in per example with `:jevalyn_live`.
    initializer "jevalyn.mock_mode" do
      Jevalyn.config.mock_mode = true if Rails.env.test? && Jevalyn.config.api_key.nil?
    end

    initializer "jevalyn.autoload_paths" do |app|
      decisions = app.root.join("app/decisions")
      app.config.autoload_paths << decisions.to_s if decisions.exist?
    end

    # `rails jevalyn:ping` -- checks the key and the network without leaving the shell.
    rake_tasks do
      load File.expand_path("tasks/jevalyn.rake", __dir__)
    end
  end
end
