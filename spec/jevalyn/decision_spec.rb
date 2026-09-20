# frozen_string_literal: true

RSpec.describe Jevalyn::Decision do
  let(:url) { "https://api.typesafe.ai/v1/systemone" }

  let(:legend) { { "0" => "trivial", "1" => "minor", "2" => "major", "3" => "critical" } }

  let(:response) do
    ResponseFixtures.systemone({
                                 "urgent" => ResponseFixtures.noul(0.92),
                                 "department" => ResponseFixtures.choice(
                                   "technical", { "billing" => 0.08, "technical" => 0.85,
                                                  "sales" => 0.07 }, 0.82
                                 ),
                                 "severity" => ResponseFixtures.score(
                                   2.4, legend, { "0" => 0.01, "1" => 0.09, "2" => 0.4, "3" => 0.5 }, 0.79
                                 )
                               })
  end

  before do
    stub_request(:post, url).to_return(
      status: 200, body: JSON.generate(response), headers: { "Content-Type" => "application/json" }
    )
  end

  describe ".evaluate" do
    subject(:result) { SupportTriage.evaluate("Help! My payouts have been failing for 3 days.") }

    it "reads each answer through a name the class declared" do
      expect(result.urgent).to eq(0.92)
      expect(result.department).to eq(:technical)
      expect(result.severity).to eq(2.4)
    end

    it "adds type-appropriate readers alongside the raw value" do
      expect(result.urgent?).to be(true)
      expect(result.department_confidence).to eq(0.82)
      expect(result.severity_label).to eq("major")
      expect(result.severity_level).to eq(2)
    end

    it "sends every declared question in one request, which is the cheap way to ask" do
      result

      expect(a_request(:post, url).with do |req|
        JSON.parse(req.body)["questions"].keys == %w[urgent department severity]
      end).to have_been_made.once
    end

    it "carries usage and the versioned model back" do
      expect(result.model).to eq("jev-1.13.0")
      expect(result.input_tokens).to eq(312)
    end

    it "exposes values as a plain hash" do
      expect(result.values).to eq(urgent: 0.92, department: :technical, severity: 2.4)
    end
  end

  describe "confidence" do
    it "is certain when every answer clears the declared threshold" do
      expect(SupportTriage.evaluate("x")).to be_certain
    end

    it "names the answers that fell short" do
      expect(SupportTriage.evaluate("x").uncertain_questions(0.8)).to contain_exactly(:severity)
    end

    it "judges a noul on distance from a coin flip, since it carries no confidence" do
      result = SupportTriage.evaluate("x")

      expect(result.urgent_certainty).to eq(0.84)
      expect(result.uncertain_questions(0.9)).to contain_exactly(:urgent, :department, :severity)
    end

    it "accepts a threshold at the call site" do
      expect(SupportTriage.evaluate("x", confidence_threshold: 0.99)).to be_uncertain
    end
  end

  describe "class definition" do
    it "rejects a duplicate question name" do
      expect do
        Class.new(described_class) do
          question :a, type: :noul, instructions: "?"
          question :a, type: :noul, instructions: "?"
        end
      end.to raise_error(Jevalyn::InvalidQuestionError, /already declares/)
    end

    it "validates the rubric when the class body runs, not when the request goes out" do
      expect do
        Class.new(described_class) { question :s, type: :score, instructions: "?", criteria: ["one"] }
      end.to raise_error(Jevalyn::InvalidQuestionError)
    end

    it "refuses to evaluate with no questions" do
      expect { Class.new(described_class).evaluate("x") }
        .to raise_error(Jevalyn::ConfigurationError, /declares no questions/)
    end

    it "rejects a threshold outside 0..1" do
      expect { Class.new(described_class) { confidence_threshold 1.5 } }
        .to raise_error(Jevalyn::ConfigurationError, /between 0 and 1/)
    end

    it "inherits questions and threshold from a parent decision" do
      child = Class.new(SupportTriage) { question :spam, type: :noul, instructions: "Spam?" }

      expect(child.question_names).to eq(%i[urgent department severity spam])
      expect(child.confidence_threshold).to eq(0.75)
      expect(SupportTriage.question_names).not_to include(:spam)
    end

    it "supports the shorthand form of each type" do
      klass = Class.new(described_class) do
        noul :urgent, "Urgent?"
        choice :team, "Which?", { a: "A", b: "B" }
        score :size, "How big?", %w[small large]
      end

      expect(klass.questions.values.map(&:type)).to eq(%i[noul choice score])
    end
  end

  describe ".model" do
    it "pins the decision to a version" do
      klass = Class.new(SupportTriage) { model "jev-1.13.0" }
      klass.evaluate("x")

      expect(a_request(:post, url).with(body: hash_including("model" => "jev-1.13.0"))).to have_been_made
    end
  end

  describe ".payload_for" do
    it "shows what would be sent without sending it" do
      payload = SupportTriage.payload_for("a ticket")

      expect(payload["state"]).to eq("a ticket")
      expect(payload["questions"]["department"]["criteria"].keys).to eq(%w[billing technical sales])
      expect(a_request(:post, url)).not_to have_been_made
    end

    it "estimates input tokens for sizing a hot path" do
      expect(SupportTriage.estimated_tokens("a ticket")).to be > 0
    end
  end
end
