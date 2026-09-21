# frozen_string_literal: true

RSpec.describe Jevalyn::Router do
  before { Jevalyn.config.mock_mode = true }

  def triage_stub(department:, confidence: 0.95)
    Jevalyn::Testing.stub(SupportTriage, confidence: confidence,
                                         urgent: true, department: department, severity: "major")
  end

  describe "as a dispatch table" do
    subject(:router) do
      described_class.new do |r|
        r.route :lookup, to: ->(state) { "looked up #{state}" }
        r.route :reason, to: ->(state, _result) { "reasoned about #{state}" }
      end
    end

    it "dispatches to a registered handler" do
      expect(router.dispatch(:lookup, state: "order-1")).to eq("looked up order-1")
    end

    it "passes the result to handlers that want it" do
      expect(router.dispatch(:reason, state: "order-1")).to eq("reasoned about order-1")
    end

    it "raises for an unregistered key, naming what it does know" do
      expect { router.dispatch(:nope, state: "x") }
        .to raise_error(Jevalyn::UnknownQuestionError, /No route for :nope.*:lookup, :reason/m)
    end

    it "uses a fallback when one is registered" do
      router.fallback(to: ->(state) { "fell back on #{state}" })

      expect(router.dispatch(:nope, state: "x")).to eq("fell back on x")
    end

    it "refuses a handler that cannot be called" do
      router.route :bad, to: "not callable"

      expect { router.dispatch(:bad, state: "x") }
        .to raise_error(Jevalyn::ConfigurationError, /must respond to #call/)
    end
  end

  describe "driven by a decision" do
    subject(:router) do
      described_class.new(SupportTriage, on: :department) do |r|
        r.route :billing,   to: ->(state) { "billing: #{state}" }
        r.route :technical, to: ->(state, result) { "technical sev #{result.severity_label}: #{state}" }
        r.route :sales,     to: ->(state) { "sales: #{state}" }
        r.uncertain_below 0.75, to: ->(state) { "human: #{state}" }
      end
    end

    it "routes on the decision's answer" do
      triage_stub(department: :technical)

      expect(router.call("payouts failing")).to eq("technical sev major: payouts failing")
    end

    it "sends a low-confidence answer to the uncertainty handler instead" do
      triage_stub(department: :billing, confidence: 0.4)

      expect(router.call("maybe a refund?")).to eq("human: maybe a refund?")
    end

    it "still routes a low-confidence answer when no floor is set" do
      plain = described_class.new(SupportTriage, on: :department) do |r|
        r.route :billing,   to: ->(state) { "billing: #{state}" }
        r.route :technical, to: ->(_state) { "technical" }
        r.route :sales,     to: ->(_state) { "sales" }
      end
      triage_stub(department: :billing, confidence: 0.3)

      expect(plain.call("x")).to eq("billing: x")
    end

    # The floor belongs to the question, so a router should not have to restate it.
    it "falls back to the question's own floor when the router names no threshold" do
      strict = Class.new(SupportTriage) do
        def self.name = "StrictTriage"

        confidence_threshold 0.9
      end

      routed = described_class.new(strict, on: :department) do |r|
        r.route :billing,   to: ->(_s) { :billing }
        r.route :technical, to: ->(_s) { :technical }
        r.route :sales,     to: ->(_s) { :sales }
        r.uncertain_below to: ->(_s) { :human }
      end

      Jevalyn::Testing.stub(strict, confidence: 0.85, urgent: true,
                                    department: :technical, severity: "major")
      expect(routed.call("x")).to eq(:human)

      Jevalyn::Testing.stub(strict, confidence: 0.95, urgent: true,
                                    department: :technical, severity: "major")
      expect(routed.call("x")).to eq(:technical)
    end

    it "exposes the decision without dispatching" do
      triage_stub(department: :sales)

      expect(router.decide("x").department).to eq(:sales)
    end

    it "accepts a Decision subclass as a handler" do
      other = Class.new(Jevalyn::Decision) { question :spam, type: :noul, instructions: "Spam?" }
      Jevalyn::Testing.stub(other, spam: true)
      triage_stub(department: :sales)
      router.route :sales, to: other

      expect(router.call("x").spam).to eq(0.95)
    end
  end

  describe "validation at build time" do
    it "rejects routing on a question the decision does not declare" do
      expect { described_class.new(SupportTriage, on: :nonsense) }
        .to raise_error(Jevalyn::ConfigurationError, /declares no question named :nonsense/)
    end

    it "rejects routing on a noul, which names no branch" do
      expect { described_class.new(SupportTriage, on: :urgent) }
        .to raise_error(Jevalyn::ConfigurationError, /routes on a :choice question/)
    end

    # The failure mode this catches is a criteria key added later with no route for it,
    # which otherwise only shows up as a production exception on an unusual ticket.
    it "rejects a route table that does not cover every option" do
      expect do
        described_class.new(SupportTriage, on: :department) do |r|
          r.route :billing, to: ->(_s) { :ok }
        end
      end.to raise_error(Jevalyn::ConfigurationError, /:technical, :sales.*no route/m)
    end

    it "accepts partial coverage when there is a fallback" do
      expect do
        described_class.new(SupportTriage, on: :department) do |r|
          r.route :billing, to: ->(_s) { :ok }
          r.fallback to: ->(_s) { :fallback }
        end
      end.not_to raise_error
    end

    it "requires a decision before #call can be used" do
      router = described_class.new { |r| r.route(:a, to: ->(_s) { :ok }) }

      expect { router.call("x") }.to raise_error(Jevalyn::ConfigurationError, /has no decision/)
    end
  end
end
