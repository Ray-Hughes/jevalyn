# frozen_string_literal: true

require "rails/generators/named_base"

module Jevalyn
  module Generators
    # rails g jevalyn:decision SupportTriage urgent:noul department:choice severity:score
    #
    # Question arguments are optional; without them you get a commented skeleton of
    # all three types to fill in.
    class DecisionGenerator < ::Rails::Generators::NamedBase
      source_root File.expand_path("templates", __dir__)

      argument :questions, type: :array, default: [], banner: "name:type name:type"

      desc "Creates a Jevalyn::Decision in app/decisions, and a spec for it."

      class_option :threshold, type: :numeric, default: 0.75,
                               desc: "Confidence floor for the decision"
      class_option :spec, type: :boolean, default: true,
                          desc: "Also generate a spec file"

      def create_decision
        template "decision.rb.tt", File.join("app/decisions", class_path, "#{file_name}.rb")
      end

      def create_spec
        return unless options[:spec]

        template "decision_spec.rb.tt", File.join("spec/decisions", class_path, "#{file_name}_spec.rb")
      end

      private

      # [[name, type], ...] -- defaults to one of each so the file is worth reading.
      def parsed_questions
        return default_questions if questions.empty?

        questions.map do |argument|
          name, type = argument.split(":", 2)
          type = (type || "noul").to_sym

          unless Jevalyn::Question::TYPES.include?(type)
            raise Thor::Error,
                  "Unknown question type #{type.inspect} for #{name}. " \
                  "Jev has three: noul, choice, score."
          end

          [name, type]
        end
      end

      def default_questions
        [%w[urgent noul].then { |n, t| [n, t.to_sym] }]
      end

      def threshold = options[:threshold]
    end
  end
end
