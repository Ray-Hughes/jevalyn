# frozen_string_literal: true

require_relative "lib/jevalyn/version"

Gem::Specification.new do |spec|
  spec.name     = "jevalyn"
  spec.version  = Jevalyn::VERSION
  spec.authors  = ["Raymond Hughes"]
  spec.email    = ["raymond.hughes@live.com"]

  spec.summary  = "The decision layer for your Rails app."
  spec.description = <<~DESC.strip
    Jevalyn bakes fast, cheap, structured decisions into a Rails app's control flow:
    routing, triage, guardrails and confidence-gated automation. It wraps TypeSafe's
    Jev System One API in a Rails-native Decision DSL, generators and test helpers.
    Jev answers typed questions -- it does not generate prose.
  DESC

  spec.homepage = "https://github.com/Ray-Hughes/jevalyn"
  spec.license  = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.metadata["homepage_uri"]       = spec.homepage
  spec.metadata["source_code_uri"]    = spec.homepage
  spec.metadata["changelog_uri"]      = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"]    = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir[
    "lib/**/*.rb",
    "lib/**/*.rake",
    "lib/generators/**/templates/**/*",
    "README.md",
    "CHANGELOG.md",
    "LICENSE.txt"
  ]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 2.0", "< 3.0"
  spec.add_dependency "railties", ">= 7.0", "< 9"
end
