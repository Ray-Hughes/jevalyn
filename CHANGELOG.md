# Changelog

All notable changes to this project are documented here. This project follows
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0]

First release. Built against the `jev-1.13` HTTP API.

### Added

- `Jevalyn::Client` — a one-to-one wrapper over `POST /v1/systemone`, with typed errors,
  automatic backoff on 429/529/5xx, and `retry-after` support.
- `Jevalyn::Decision` — the question DSL, validated at class-definition time, with a
  generated reader per question on the result.
- `Jevalyn::Answer` — `Noul`, `Choice` and `Score` wrappers over the three answer shapes.
- `Jevalyn::Guardrail` — a single-noul gate answering `#allow?` / `#deny?`, denying rather
  than failing open when the API is unreachable.
- `Jevalyn::Router` — dispatch on a choice answer, with a confidence floor and
  build-time checking that every option has a route.
- `Jevalyn::State` — the `#jevalyn_state` convention, with an ActiveRecord adapter.
- `Jevalyn::Testing` — local stubs, RSpec and Minitest integration, and a cassette
  recorder keyed on request content.
- `evaluate_later` for ActiveJob.
- Generators: `jevalyn:install`, `jevalyn:decision`, `jevalyn:guardrail`.
- Rake tasks: `jevalyn:ping`, `jevalyn:decisions`.

### Notes

Two details of the API are easy to get wrong, and Jevalyn models them explicitly:

- **Noul answers carry no `confidence`.** TypeSafe returns `confidence` on Choice and
  Score answers only. `Answer::Noul#confidence` is `nil`; `#certainty` derives a
  comparable number from the probability's distance off `0.5` so thresholds work
  uniformly.
- **Score answers are a weighted Float, not a level label.** `2.4` lands between levels
  on purpose. `#label` gives the nearest level's description.
