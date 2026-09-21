# frozen_string_literal: true

# A confidence floor is a statement about what a wrong answer costs, and different
# questions in one decision rarely cost the same. These cover the per-question floors
# and how a call site overrides them.
RSpec.describe "per-question confidence thresholds" do # rubocop:disable RSpec/DescribeClass
  let(:url) { "https://api.typesafe.ai/v1/systemone" }

  # Misrouting a ticket is recoverable, so :severity can be read loosely; sending it
  # to the wrong team is not, so :department has to be surer.
  let(:decision) do
    Class.new(Jevalyn::Decision) do
      def self.name = "MixedTriage"

      question :urgent, type: :noul, instructions: "Urgent?"

      question :department, type: :choice,
                            instructions: "Which team?",
                            criteria: { billing: "Payments", technical: "Bugs" },
                            confidence_threshold: 0.8

      question :severity, type: :score,
                          instructions: "How severe?",
                          criteria: %w[minor major critical],
                          confidence_threshold: 0.6

      confidence_threshold 0.75
    end
  end

  def respond(department_confidence:, severity_confidence:, noul: 0.92)
    body = ResponseFixtures.systemone({
                                        "urgent" => ResponseFixtures.noul(noul),
                                        "department" => ResponseFixtures.choice(
                                          "technical", { "billing" => 0.2,
                                                         "technical" => 0.8 }, department_confidence
                                        ),
                                        "severity" => ResponseFixtures.score(
                                          1.0, { "0" => "minor", "1" => "major", "2" => "critical" },
                                          { "0" => 0.2, "1" => 0.6, "2" => 0.2 }, severity_confidence
                                        )
                                      })

    stub_request(:post, url).to_return(
      status: 200, body: JSON.generate(body), headers: { "Content-Type" => "application/json" }
    )
  end

  describe "declaring a floor per question" do
    it "resolves each question's own floor, falling back to the class default" do
      expect(decision.thresholds).to eq(urgent: 0.75, department: 0.8, severity: 0.6)
    end

    it "judges each answer against its own floor" do
      respond(department_confidence: 0.7, severity_confidence: 0.65)

      result = decision.evaluate("x")

      expect(result.uncertain_questions).to eq([:department])
      expect(result).to be_uncertain
    end

    # The whole point: 0.65 is not good enough for :department and is fine for
    # :severity, and one number for the decision cannot express that.
    it "lets one answer pass and another fail at the same confidence" do
      respond(department_confidence: 0.65, severity_confidence: 0.65)

      result = decision.evaluate("x")

      expect(result.department_certain?).to be(false)
      expect(result.severity_certain?).to be(true)
    end

    it "is certain when every answer clears its own floor" do
      respond(department_confidence: 0.85, severity_confidence: 0.61)

      expect(decision.evaluate("x")).to be_certain
    end

    it "reports the floor each answer was judged against" do
      respond(department_confidence: 0.85, severity_confidence: 0.61)
      result = decision.evaluate("x")

      expect(result.thresholds).to eq(urgent: 0.75, department: 0.8, severity: 0.6)
      expect(result.department_threshold).to eq(0.8)
      expect(result.threshold_for(:severity)).to eq(0.6)
    end

    it "reports how far each answer sits from its floor" do
      respond(department_confidence: 0.7, severity_confidence: 0.65)

      margins = decision.evaluate("x").certainty_margins

      expect(margins[:department]).to be_within(1e-9).of(-0.1)
      expect(margins[:severity]).to be_within(1e-9).of(0.05)
    end

    it "measures a noul against its floor by distance off a coin flip" do
      respond(department_confidence: 0.9, severity_confidence: 0.9, noul: 0.6)

      # 0.6 is only 0.2 of the way off a coin flip, well under the 0.75 default.
      expect(decision.evaluate("x").uncertain_questions).to eq([:urgent])
    end

    it "rejects a floor outside 0..1, naming the question" do
      expect do
        Class.new(Jevalyn::Decision) do
          question :a, type: :noul, instructions: "?", confidence_threshold: 1.5
        end
      end.to raise_error(Jevalyn::ConfigurationError, /confidence_threshold for :a/)
    end

    it "carries per-question floors down to a subclass" do
      child = Class.new(decision) do
        question :spam, type: :noul, instructions: "Spam?", confidence_threshold: 0.2
      end

      expect(child.thresholds).to eq(urgent: 0.75, department: 0.8, severity: 0.6, spam: 0.2)
    end

    it "takes a floor through the shorthand form too" do
      klass = Class.new(Jevalyn::Decision) do
        choice :team, "Which?", { a: "A", b: "B" }, confidence_threshold: 0.9
        score :size, "How big?", %w[small large], confidence_threshold: 0.3
        noul :spam, "Spam?", confidence_threshold: 0.4
      end

      expect(klass.thresholds).to eq(team: 0.9, size: 0.3, spam: 0.4)
    end
  end

  describe "overriding at the call site" do
    before { respond(department_confidence: 0.85, severity_confidence: 0.65) }

    it "applies one number to every question with confidence_threshold:" do
      result = decision.evaluate("x", confidence_threshold: 0.9)

      expect(result.thresholds.values).to all(eq(0.9))
      expect(result.uncertain_questions).to contain_exactly(:urgent, :department, :severity)
    end

    it "names individual questions with thresholds:" do
      result = decision.evaluate("x", thresholds: { severity: 0.99 })

      expect(result.thresholds).to eq(urgent: 0.75, department: 0.8, severity: 0.99)
      expect(result.uncertain_questions).to eq([:severity])
    end

    it "lets thresholds: win over a blanket confidence_threshold:" do
      result = decision.evaluate("x", confidence_threshold: 0.99, thresholds: { severity: 0.1 })

      expect(result.thresholds).to eq(urgent: 0.99, department: 0.99, severity: 0.1)
    end

    it "catches a misspelled question rather than silently ignoring the floor" do
      expect { decision.evaluate("x", thresholds: { deptartment: 0.9 }) }
        .to raise_error(Jevalyn::ConfigurationError, /declares no question named :deptartment/)
    end

    it "still accepts a one-off number on certain? for a quick stricter read" do
      result = decision.evaluate("x")

      expect(result.certain?).to be(true)
      expect(result.certain?(0.9)).to be(false)
      expect(result.department_certain?(0.9)).to be(false)
    end
  end

  describe "a decision that sets no floors at all" do
    let(:loose) do
      Class.new(Jevalyn::Decision) { question :urgent, type: :noul, instructions: "Urgent?" }
    end

    it "is certain, because nothing was asked for" do
      stub_request(:post, url).to_return(
        status: 200,
        body: JSON.generate(ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.5) })),
        headers: { "Content-Type" => "application/json" }
      )

      result = loose.evaluate("x")

      expect(result.thresholds).to eq(urgent: nil)
      expect(result).to be_certain
    end
  end
end

RSpec.describe "threshold test helpers" do # rubocop:disable RSpec/DescribeClass
  let(:decision) do
    Class.new(Jevalyn::Decision) do
      def self.name = "HelperTriage"

      question :department, type: :choice, instructions: "?",
                            criteria: { billing: "b", technical: "t" },
                            confidence_threshold: 0.8

      question :severity, type: :score, instructions: "?",
                          criteria: %w[minor major],
                          confidence_threshold: 0.6
    end
  end

  before { Jevalyn.config.mock_mode = true }

  # Without per-question confidence in the stub there is no way to write the test
  # this whole feature exists for: one answer under its floor, another over its own.
  it "stubs confidence per question" do
    stub_jevalyn(decision, department: :technical, severity: "major",
                           confidence: { department: 0.7, severity: 0.65 })

    result = decision.evaluate("x")

    expect(result.department_confidence).to eq(0.7)
    expect(result.severity_confidence).to eq(0.65)
    expect(result).to have_uncertain_questions(:department)
  end

  it "falls back to the default confidence for questions the hash does not name" do
    stub_jevalyn(decision, department: :technical, severity: "major",
                           confidence: { department: 0.7 })

    expect(decision.evaluate("x").severity_confidence).to eq(Jevalyn::Testing::DEFAULT_CONFIDENCE)
  end

  it "exposes Result's per-question predicates as RSpec matchers for free" do
    stub_jevalyn(decision, department: :technical, severity: "major",
                           confidence: { department: 0.7, severity: 0.65 })

    result = decision.evaluate("x")

    expect(result).not_to be_department_certain
    expect(result).to be_severity_certain
  end

  it "names floors and certainties when the uncertain set is wrong" do
    stub_jevalyn(decision, department: :technical, severity: "major",
                           confidence: { department: 0.7, severity: 0.65 })

    expect { expect(decision.evaluate("x")).to have_uncertain_questions(:severity) }
      .to raise_error(RSpec::Expectations::ExpectationNotMetError, /department: certainty=0.7 floor=0.8/)
  end
end
