# frozen_string_literal: true

require "rails/generators/named_base"

module Jevalyn
  module Generators
    # rails g jevalyn:guardrail ToolCall
    class GuardrailGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      desc "Creates a Jevalyn::Guardrail in app/decisions, and a spec for it."

      class_option :question, type: :string, default: "safe",
                              desc: "Name of the single noul question"
      class_option :allow_above, type: :numeric, default: 0.9,
                                 desc: "Probability required to allow"
      class_option :spec, type: :boolean, default: true

      def create_guardrail
        template "guardrail.rb.tt", File.join("app/decisions", class_path, "#{file_name}.rb")
      end

      def create_spec
        return unless options[:spec]

        template "guardrail_spec.rb.tt", File.join("spec/decisions", class_path, "#{file_name}_spec.rb")
      end

      private

      def question_name = options[:question]

      def allow_above = options[:allow_above]
    end
  end
end
