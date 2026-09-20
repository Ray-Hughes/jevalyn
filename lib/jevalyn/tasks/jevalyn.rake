# frozen_string_literal: true

namespace :jevalyn do
  desc "Check that Jevalyn can reach the TypeSafe API with the configured key"
  task ping: :environment do
    config = Jevalyn.config
    puts "base url: #{config.base_url}"
    puts "model:    #{config.default_model}"
    puts "key:      #{config.api_key ? "set (#{config.api_key[0, 6]}...)" : "MISSING"}"
    puts "mock:     #{config.mock_mode}"

    models = Jevalyn.client.models
    puts "\nreachable. models available to this account:"
    models.each { |m| puts "  #{m["name"]} - #{m["description"]}" }
  rescue Jevalyn::Error => e
    abort "\n#{e.class}: #{e.message}"
  end

  desc "List the Decision and Guardrail classes this app defines"
  task decisions: :environment do
    Rails.application.eager_load!

    [Jevalyn::Guardrail, Jevalyn::Decision].each do |base|
      found = base.subclasses.reject { |k| k <= Jevalyn::Guardrail && base == Jevalyn::Decision }
      next if found.empty?

      puts "#{base.name.demodulize}s:"
      found.sort_by(&:name).each do |klass|
        questions = klass.questions.values.map { |q| "#{q.name}:#{q.type}" }.join(" ")
        puts "  #{klass.name.ljust(32)} #{questions}"
      end
      puts
    end
  end
end
