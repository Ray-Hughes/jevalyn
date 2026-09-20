# frozen_string_literal: true

RSpec.describe Jevalyn::Testing do
  before { Jevalyn.config.mock_mode = true }

  describe ".stub" do
    it "expands friendly values into a response the API could have returned" do
      described_class.stub(SupportTriage, urgent: true, department: :technical, severity: "major")

      result = SupportTriage.evaluate("payouts failing")

      expect(result.urgent).to eq(0.95)
      expect(result.department).to eq(:technical)
      expect(result.severity_label).to eq("major")
      expect(result.department_probabilities.values.sum).to be_within(0.001).of(1.0)
    end

    it "makes no HTTP request at all" do
      described_class.stub(SupportTriage, urgent: true, department: :billing, severity: 0)

      SupportTriage.evaluate("x")

      expect(a_request(:post, "https://api.typesafe.ai/v1/systemone")).not_to have_been_made
    end

    it "needs no API key, because nothing is sent" do
      Jevalyn.config.api_key = nil
      described_class.stub(SupportTriage, urgent: false, department: :sales, severity: 1)

      expect { SupportTriage.evaluate("x") }.not_to raise_error
    end

    it "takes a float for a noul when the exact probability matters" do
      described_class.stub(SupportTriage, urgent: 0.61, department: :sales, severity: 1)

      expect(SupportTriage.evaluate("x").urgent).to eq(0.61)
    end

    it "takes a level index or its label for a score" do
      described_class.stub(SupportTriage, urgent: true, department: :sales, severity: 3)

      expect(SupportTriage.evaluate("x").severity_label).to eq("critical")
    end

    it "lowers confidence on request, to exercise the uncertain path" do
      described_class.stub(SupportTriage, confidence: 0.4, urgent: true, department: :sales, severity: 1)

      expect(SupportTriage.evaluate("x")).to be_uncertain
    end

    it "answers differently per state when given a block" do
      described_class.stub(SupportTriage) do |state|
        { urgent: state.include?("!"), department: :technical, severity: 1 }
      end

      expect(SupportTriage.evaluate("help!").urgent?).to be(true)
      expect(SupportTriage.evaluate("hello").urgent?).to be(false)
    end

    it "rejects an option the decision never declared" do
      described_class.stub(SupportTriage, urgent: true, department: :legal, severity: 1)

      expect { SupportTriage.evaluate("x") }
        .to raise_error(ArgumentError, /not an option of :department/)
    end

    it "rejects a level the rubric does not have" do
      described_class.stub(SupportTriage, urgent: true, department: :sales, severity: "apocalyptic")

      expect { SupportTriage.evaluate("x") }.to raise_error(ArgumentError, /not a level of :severity/)
    end
  end

  describe "an unstubbed evaluation" do
    it "raises rather than quietly inventing an answer" do
      expect { SupportTriage.evaluate("x") }
        .to raise_error(described_class::NoStubError, /nothing is stubbed/)
    end

    it "names the questions still missing a value" do
      described_class.stub(SupportTriage, urgent: true)

      expect { SupportTriage.evaluate("x") }
        .to raise_error(described_class::NoStubError, /No stubbed value for :department/)
    end
  end

  describe ".forbid" do
    it "fails the example if the decision is evaluated at all" do
      described_class.forbid(SupportTriage)

      expect { SupportTriage.evaluate("x") }.to raise_error(described_class::NoStubError, /forbidden/)
    end
  end

  describe ".calls" do
    it "records what was asked, so a spec can assert on the state sent" do
      described_class.stub(SupportTriage, urgent: true, department: :sales, severity: 1)

      SupportTriage.evaluate("first")
      SupportTriage.evaluate("second")

      expect(described_class.calls.map(&:state)).to eq(%w[first second])
      expect(described_class.calls.map(&:decision).uniq).to eq([SupportTriage])
    end
  end

  describe "matchers" do
    before { stub_jevalyn(SupportTriage, urgent: true, department: :technical, severity: 2) }

    it "asserts a decision ran" do
      SupportTriage.evaluate("x")

      expect(SupportTriage).to have_been_evaluated.once
    end

    it "asserts a decision did not run" do
      expect(SupportTriage).not_to have_been_evaluated
    end

    it "asserts on the state a decision saw" do
      SupportTriage.evaluate("a ticket")

      expect(SupportTriage).to have_been_evaluated.with_state("a ticket")
      expect(jevalyn_states_for(SupportTriage)).to eq(["a ticket"])
    end

    it "asserts certainty" do
      expect(SupportTriage.evaluate("x")).to be_certain_above(0.8)
    end
  end
end
