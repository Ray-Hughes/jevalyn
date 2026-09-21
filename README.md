<div align="center">

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="https://raw.githubusercontent.com/Ray-Hughes/jevalyn/main/docs/assets/logo-dark.png">
  <img src="https://raw.githubusercontent.com/Ray-Hughes/jevalyn/main/docs/assets/logo.png" alt="Jevalyn" width="340">
</picture>

**Fast, cheap, structured decisions baked into your Rails app's control flow.**

[![Gem](https://img.shields.io/gem/v/jevalyn?color=2DB88A)](https://rubygems.org/gems/jevalyn)
[![Downloads](https://img.shields.io/gem/dt/jevalyn?color=21283C)](https://rubygems.org/gems/jevalyn)
[![CI](https://github.com/Ray-Hughes/jevalyn/actions/workflows/ci.yml/badge.svg)](https://github.com/Ray-Hughes/jevalyn/actions/workflows/ci.yml)
[![Ruby](https://img.shields.io/badge/ruby-%3E%3D%203.1-CC342D)](https://www.ruby-lang.org)
[![Rails](https://img.shields.io/badge/rails-%3E%3D%207.0-D30001)](https://rubyonrails.org)
[![Jev](https://img.shields.io/badge/jev-1.13-21283C)](https://docs.typesafe.ai)
[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE.txt)

[Install](#install) · [Decisions](#decisions) · [Guardrails](#guardrails) · [Router](#router) · [Testing](#testing)

</div>

---

```ruby
class SupportTriage < Jevalyn::Decision
  question :department, type: :choice,
    instructions: "Which team should handle this?",
    criteria: {
      billing:   "Payments, invoicing, refunds",
      technical: "Bugs, outages, integrations",
      sales:     "Pricing, upgrades, new accounts"
    }

  confidence_threshold 0.75
end

result = SupportTriage.evaluate(ticket.body)

result.department   # => :technical
result.certain?     # => true
```

**Jevalyn is the decision layer for your Rails app**, built on
[Jev](https://docs.typesafe.ai). That is a routing decision made by a model, inside a
Rails request, in about as long as a database query. Not a prompt, not a parsed JSON
blob, not a retry loop around something that might return prose this time.

## What this is, and what it is not

Jevalyn wraps [TypeSafe's Jev](https://docs.typesafe.ai), a **System One** model. You
give it a `state` and a set of typed questions; it gives back typed, calibrated
answers. There are exactly three kinds of question:

| Type | Ask it | Get back |
| --- | --- | --- |
| `noul` | a yes/no question | the probability the answer is yes, `0.0`–`1.0` |
| `choice` | pick one of up to 255 options you define | the winner, the full distribution, a confidence |
| `score` | rate against 2–10 ordered levels you define | a weighted score, the distribution, a confidence |

**Jev does not generate text.** No summaries, no drafts, no open-ended reasoning, no
tool calls. If you need prose, you need an LLM, and Jevalyn will happily route to one
(see [Router](#router)) — but it will not pretend to be one.

What it is good at is the decision *around* the work: which queue does this belong in,
is this safe to auto-approve, how severe is this, does this comment need a human, which
of these 200 documents actually answers the question. Those are cheap, fast, and
type-safe here, and expensive, slow, and stringly-typed anywhere else.

You can build anything on top of it — trade screening, recipe filtering, content
moderation. "Use Jevalyn for recipes" means *classifying and scoring* recipes, not
writing them.

## Install

```ruby
# Gemfile
gem "jevalyn"
```

```console
$ bundle install
$ bin/rails g jevalyn:install
```

That writes `config/initializers/jevalyn.rb` and creates `app/decisions/`. Then put
your key in the environment:

```console
$ export TYPESAFE_API_KEY=ts_...
$ bin/rails jevalyn:ping
```

Get a key at [typesafe.ai](https://typesafe.ai). Jev bills on **input tokens only** —
output tokens are free — at roughly $0.042 per million input tokens as of `jev-1.13`.
A support ticket costs a fraction of a cent to triage. Check
[the models page](https://docs.typesafe.ai/models) for current pricing and rate limits;
they are still moving.

## Decisions

A `Jevalyn::Decision` is a named set of questions your app asks about a piece of state.

```console
$ bin/rails g jevalyn:decision SupportTriage urgent:noul department:choice severity:score
```

```ruby
class SupportTriage < Jevalyn::Decision
  question :urgent, type: :noul,
    instructions: "Does this convey urgency?",
    criteria: { true: "Explicitly time-sensitive", false: "No urgency expressed" }

  question :department, type: :choice,
    instructions: "Which team should handle this?",
    criteria: {
      billing:   "Payments, invoicing, refunds",
      technical: "Bugs, outages, integrations",
      sales:     "Pricing, upgrades, new accounts"
    }

  question :severity, type: :score,
    instructions: "How severe is this issue?",
    criteria: ["trivial", "minor", "major", "critical"]

  confidence_threshold 0.75
end
```

Every question is validated when the class body runs, so a rubric with eleven score
levels or a `:choice` with no criteria fails on boot — not as a 422 on a Friday
afternoon.

All three questions go out in **one request**. Jev reads the state once and evaluates
every question against it in parallel, which is both cheaper and faster than asking
three times. Add speculative questions freely; they cost a few tokens each.

### Reading the result

```ruby
result = SupportTriage.evaluate(ticket.body)

result.urgent               # => 0.92        the raw probability
result.urgent?              # => true        at the default 0.5 cutoff
result.urgent?(0.95)        # => false       your cutoff, your call

result.department           # => :technical
result.department_confidence     # => 0.82
result.department_probabilities  # => { "billing" => 0.08, "technical" => 0.85, ... }
result.department_answer.runner_up  # => :billing

result.severity             # => 2.4         weighted, lands between levels
result.severity_label       # => "major"     nearest level
result.severity_level       # => 2

result.certain?             # => true        every answer cleared 0.75
result.uncertain_questions  # => []          or the names that did not
result.model                # => "jev-1.13.0"
result.input_tokens         # => 312
result.values               # => { urgent: 0.92, department: :technical, severity: 2.4 }
```

Two things here differ from what you might expect, and both come straight from the API:

- **A score is a Float, not a label.** `2.4` means past *major* and heading for
  *critical*. Use `severity_label` when you want the nearest level's name, and
  `severity` itself when you want to do arithmetic.
- **A noul has no confidence.** Jev returns `confidence` on Choice and Score answers
  only — for a noul, the probability *is* the answer, and `0.5` is the model telling
  you it does not know. Jevalyn fills the gap with `certainty`, derived from how far
  the value sits from a coin flip, so `certain?` works uniformly across all three
  types. That number is Jevalyn's arithmetic, not TypeSafe's; `confidence` stays `nil`
  so you always know which is which.

### Confidence

Confidence is the second axis. The answer tells you *what*; confidence tells you
*whether to act*.

```ruby
result = RefundDecision.evaluate(request)

if result.uncertain?
  HumanReview.enqueue(request)     # the model said "I'm not sure"
elsif result.approve?
  Refund.issue(request)
end
```

A threshold is not one number for your whole app — and usually not one number for a
whole decision either. Misrouting a ticket is recoverable; sending it to a team that
cannot help is worse; auto-approving a refund is worse again. So a floor belongs to
the **question**, and `confidence_threshold` on the class is just the default for
questions that do not name their own:

```ruby
class SupportTriage < Jevalyn::Decision
  question :department, type: :choice,
    instructions: "Which team should handle this?",
    criteria: { ... },
    confidence_threshold: 0.8      # routing to the wrong team wastes a day

  question :severity, type: :score,
    instructions: "How severe is this issue?",
    criteria: ["trivial", "minor", "major", "critical"],
    confidence_threshold: 0.6      # a roughly-right severity is still useful

  confidence_threshold 0.75        # the default for anything above without one
end
```

Each answer is then judged against its own floor:

```ruby
result = SupportTriage.evaluate(ticket.body)

result.certain?              # => false — every answer against its own floor
result.uncertain_questions   # => [:department] — severity was fine at 0.65
result.department_certain?   # => false
result.severity_certain?     # => true

result.thresholds            # => { urgent: 0.75, department: 0.8, severity: 0.6 }
result.department_threshold  # => 0.8
result.certainty_margins     # => { urgent: 0.15, department: -0.1, severity: 0.05 }
```

`certainty_margins` is how far each answer sits above its floor — negative means it
missed. Log it for a week and you will know which floors you actually set correctly.

Override at the call site when the stakes change for one call. `confidence_threshold:`
applies one number to everything; `thresholds:` names questions individually and wins
where both are given:

```ruby
SupportTriage.evaluate(body, confidence_threshold: 0.95)     # stricter about all of it
SupportTriage.evaluate(body, thresholds: { department: 0.9 }) # stricter about one
```

So the floor for a question resolves, most specific first:

1. `thresholds:` at the call site
2. `confidence_threshold:` at the call site
3. `confidence_threshold:` on the question
4. `confidence_threshold` on the decision
5. `Jevalyn.config.default_confidence_threshold`

With none of them set, `certain?` is `true` — nothing was asked for.

A noul carries no confidence, so its floor is measured against `certainty`: how far
the probability sits from a coin flip. `0.6` against a floor of `0.75` is uncertain;
`0.92` clears it.

### State

Anything JSON-shaped works: a String, a Hash, an Array, an ActiveRecord model.

```ruby
SupportTriage.evaluate(ticket.body)                        # a string
SupportTriage.evaluate({ subject: s, body: b, plan: "pro" }) # a hash
SupportTriage.evaluate(conversation.messages)              # an array
SupportTriage.evaluate(ticket)                             # an AR model
```

For a model, define `#jevalyn_state` and send only what the decision needs. The default
is `as_json`, which ships every column — wasteful in tokens and careless with data that
did not need to leave the building.

```ruby
class Ticket < ApplicationRecord
  def jevalyn_state
    { subject:, body:, plan: account.plan, previous_tickets: account.tickets.count }
  end
end
```

Jev's budget is 64k tokens per request, and 32k for the state plus the longest single
question. `SupportTriage.estimated_tokens(state)` gives a rough count before you send.

### Checking cost before you ship

```ruby
SupportTriage.payload_for(ticket.body)   # exactly what would be sent, unsent
SupportTriage.estimated_tokens(ticket.body)
```

## Guardrails

A `Guardrail` is a Decision narrowed to one job: should this be allowed through?

```console
$ bin/rails g jevalyn:guardrail ToolCall
```

```ruby
class ToolCallGuardrail < Jevalyn::Guardrail
  question :safe_to_execute, type: :noul,
    instructions: "Is this tool call safe to run without human review?",
    criteria: {
      true:  "Read-only, scoped to the current user's own data",
      false: "Writes, deletes, spends money, or touches another account"
    }

  allow_above 0.95
  on_error :deny
end

ToolCallGuardrail.check(tool_call).allow?
```

One noul question, and `allow_above` is the probability it must reach. The default is
`0.5` — a coin flip — which is almost certainly not what you want in front of anything
destructive.

If the API call itself fails, a guardrail **denies** rather than failing open:

```ruby
result = ToolCallGuardrail.check(payload)

result.deny?      # => true
result.failed?    # => true   — denied because TypeSafe was unreachable
result.error      # => #<Jevalyn::OverloadedError ...>
```

Set `on_error :raise` if you would rather handle the outage yourself.

## Router

A dispatch table with a confidence floor underneath it. This is where Jev hands off to
something slower when it is not sure.

```ruby
router = Jevalyn::Router.new(SupportTriage, on: :department) do |r|
  r.route :billing,   to: BillingInbox
  r.route :technical, to: ->(ticket, result) { Oncall.page(ticket, result.severity) }
  r.route :sales,     to: SalesInbox

  r.uncertain_below 0.75, to: HumanQueue
end

router.call(ticket)
```

Handlers are anything responding to `#call`, or another `Jevalyn::Decision`. They get
`(state, result)` if they take two arguments and `(state)` if they take one.

The router checks at build time that every option your `:choice` can return has a route
— so adding a fourth department and forgetting to route it is a boot error, not a
production exception on an unusual ticket.

Without a decision it is a plain dispatch table:

```ruby
router = Jevalyn::Router.new do |r|
  r.route :lookup, to: OrderLookup
  r.route :reason, to: llm_client
end

router.dispatch(:lookup, state: order)
```

Keep it thin. If a route needs branching logic, that logic belongs in the handler.

## Testing

TypeSafe has no sandbox key, so `mock_mode` is entirely local: with it on, the client
never opens a connection.

```ruby
# spec/spec_helper.rb
require "jevalyn/testing/rspec"
```

That turns mock mode on for the suite, resets stubs between examples, and adds helpers:

```ruby
it "routes a payment failure to the technical team" do
  stub_jevalyn(SupportTriage, urgent: true, department: :technical, severity: "major")

  expect(TriageJob.perform_now(ticket).queue).to eq("technical")
  expect(SupportTriage).to have_been_evaluated.once
end
```

Stubbed values are written the way you would assert on them — `true`, `:technical`,
`"major"` — and expanded into a response the real API could have returned, probability
distribution and all. An unstubbed evaluation **raises**, so a new question added to a
decision surfaces in the suite rather than silently answering `nil`.

```ruby
stub_jevalyn(SupportTriage, urgent: 0.61, ...)                 # exact probability
stub_jevalyn(SupportTriage, confidence: 0.4, ...)              # exercise the uncertain path
stub_jevalyn(SupportTriage) { |state| { urgent: state.include?("!") } }   # per-state
forbid_jevalyn(SupportTriage)                                  # assert it is never called
```

`confidence:` also takes a Hash, which is how you test [per-question
floors](#confidence) — one answer landing under its floor while another clears its own:

```ruby
it "escalates a low-confidence department but keeps the severity" do
  stub_jevalyn(SupportTriage,
    department: :technical, severity: "major",
    confidence: { department: 0.7, severity: 0.65 })

  result = SupportTriage.evaluate(ticket.body)

  expect(result).to have_uncertain_questions(:department)
  expect(result).to be_severity_certain
end
```

`have_uncertain_questions` prints every answer's certainty next to its floor when it
fails, which is what you need to see when a threshold is set wrong. The per-question
predicates (`be_department_certain`, `be_severity_certain`) come from `Result` through
RSpec's own predicate matchers — there is nothing to register.

Minitest works the same way via `require "jevalyn/testing/minitest"`.

### Cassettes

For the handful of tests that should run against real answers, record once and replay:

```ruby
jevalyn_cassette("spec/cassettes/triage.json") do
  result = SupportTriage.evaluate(File.read("spec/fixtures/payout_failure.txt"))
  expect(result.department).to eq(:technical)
end
```

The first run with a real key records; every run after replays. Requests are keyed by a
digest of the exact body sent, so changing a rubric misses the cassette rather than
replaying a stale answer against a question you no longer ask. Commit the file.

### Testing against the live model

Stubs prove your *code* is right. They cannot prove your *rubric* is right — and a
rubric is the part that drifts, both when you reword it and when `jev-latest` moves
under you. Keep a handful of real inputs whose answer you are sure of, tag them
`:jevalyn_live`, and run them deliberately:

```ruby
it "recognises a payout outage as technical", :jevalyn_live do
  expect(SupportTriage.evaluate(payout_outage_ticket).department).to eq(:technical)
end
```

## Background evaluation

Jev answers in well under a second, so the default advice is to call `evaluate` inline
and keep the decision in your control flow. That is the whole point of a System One
model — it is fast enough to be part of the request.

Use the queue when the decision is genuinely not on the critical path: backfills, batch
scoring, or anywhere a third-party outage must not take a request down with it.

```ruby
SupportTriage.evaluate_later(ticket, on: TicketRouter)
# => TicketRouter.call(result, ticket)
```

The handler is named rather than passed as a block, because a block cannot be
serialised onto a queue.

## Configuration

```ruby
Jevalyn.configure do |c|
  c.api_key = ENV["TYPESAFE_API_KEY"]
  c.default_model = "jev-latest"
  c.timeout = 10
  c.open_timeout = 5
  c.max_retries = 2
  c.mock_mode = Rails.env.test?
end
```

`jev-latest` is an alias, and an alias moves when TypeSafe ships a release. Every
`Result` reports the versioned model that actually answered (`result.model`), so log it.
Once you have tuned thresholds against a version, pin it:

```ruby
class RefundDecision < Jevalyn::Decision
  model "jev-1.13.0"
end
```

## Errors

| Error | When |
| --- | --- |
| `Jevalyn::ConfigurationError` | no API key, empty state, a malformed decision |
| `Jevalyn::InvalidQuestionError` | a rubric that cannot be sent — raised at class definition |
| `Jevalyn::AuthenticationError` | 401 |
| `Jevalyn::InvalidRequestError` | 422, with the offending field in `#body` |
| `Jevalyn::RateLimitError` | 429 — retried automatically |
| `Jevalyn::OverloadedError` | 529 — retried automatically |
| `Jevalyn::TimeoutError` | the request did not complete |
| `Jevalyn::ConnectionError` | TypeSafe was unreachable |

429, 529 and 5xx are retried with exponential backoff, honouring the API's
`retry-after` header when it sends one. Everything else fails immediately, because it
would fail identically on a retry.

**Low confidence is not an error.** It is the model doing its job. `result.uncertain?`
is a branch in your code, not a rescue.

## Generators

```console
$ bin/rails g jevalyn:install
$ bin/rails g jevalyn:decision SupportTriage urgent:noul department:choice
$ bin/rails g jevalyn:guardrail ToolCall --allow-above 0.95
```

```console
$ bin/rails jevalyn:ping         # check key, network, available models
$ bin/rails jevalyn:decisions    # list every Decision and Guardrail in the app
```

## Requirements

Ruby 3.1+, Rails 7.0+. Jevalyn is Rails-only by design — the generators, the railtie,
and the ActiveRecord state conventions are the reason it exists rather than a raw
client.

## Relationship to TypeSafe

Jevalyn is an unofficial, community-maintained gem. It is not built, endorsed, or
supported by TypeSafe AI. "Jev" and "TypeSafe" are theirs. For the API itself, the
canonical reference is [docs.typesafe.ai](https://docs.typesafe.ai).

## License

MIT. See [LICENSE.txt](LICENSE.txt).
