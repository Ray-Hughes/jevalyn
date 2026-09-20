# frozen_string_literal: true

require "rails/generators/base"

module Jevalyn
  module Generators
    # rails g jevalyn:install
    class InstallGenerator < ::Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Creates config/initializers/jevalyn.rb and an app/decisions directory."

      class_option :api_key_env, type: :string, default: "TYPESAFE_API_KEY",
                                 desc: "Environment variable holding the TypeSafe API key"

      def create_initializer
        template "jevalyn.rb.tt", "config/initializers/jevalyn.rb"
      end

      def create_decisions_directory
        empty_directory "app/decisions"
        create_file "app/decisions/.keep" unless File.exist?(File.join(destination_root,
                                                                       "app/decisions/.keep"))
      end

      def report
        say ""
        say "Jevalyn is installed.", :green
        say ""
        say "  1. Put your key in the environment:  #{options[:api_key_env]}=ts_..."
        say "  2. Generate a decision:              rails g jevalyn:decision SupportTriage"
        say "  3. Check the connection:             rails jevalyn:ping"
        say ""
      end
    end
  end
end
