# frozen_string_literal: true

RSpec.describe Jevalyn::Question do
  describe "noul" do
    it "builds the documented payload" do
      question = described_class.build(:urgent, type: :noul, instructions: "Urgent?")

      expect(question.to_payload).to eq("type" => "noul", "instructions" => "Urgent?")
    end

    it "includes optional true/false criteria" do
      question = described_class.build(
        :urgent, type: :noul, instructions: "Urgent?",
                 criteria: { true: "Time-sensitive", false: "No urgency" }
      )

      expect(question.to_payload["criteria"]).to eq("true" => "Time-sensitive", "false" => "No urgency")
    end

    it "rejects criteria keys the API does not accept" do
      expect do
        described_class.build(:urgent, type: :noul, instructions: "Urgent?", criteria: { maybe: "?" })
      end.to raise_error(Jevalyn::InvalidQuestionError, /only :true and :false/)
    end
  end

  describe "choice" do
    it "serialises criteria with string keys and keeps nil descriptions" do
      question = described_class.build(
        :department, type: :choice, instructions: "Which team?",
                     criteria: { billing: "Payments", technical: nil }
      )

      expect(question.to_payload).to eq(
        "type" => "choice",
        "instructions" => "Which team?",
        "criteria" => { "billing" => "Payments", "technical" => nil }
      )
    end

    it "requires criteria" do
      expect { described_class.build(:department, type: :choice, instructions: "Which?") }
        .to raise_error(Jevalyn::InvalidQuestionError, /non-empty Hash/)
    end

    it "rejects more options than Jev accepts" do
      criteria = (1..256).to_h { |i| [:"option_#{i}", "n"] }

      expect { described_class.build(:big, type: :choice, instructions: "?", criteria: criteria) }
        .to raise_error(Jevalyn::InvalidQuestionError, /at most 255/)
    end

    it "allows exactly 255 options" do
      criteria = (1..255).to_h { |i| [:"option_#{i}", "n"] }

      expect(described_class.build(:big, type: :choice, instructions: "?", criteria: criteria).options.size)
        .to eq(255)
    end
  end

  describe "score" do
    it "serialises criteria as an ordered array" do
      question = described_class.build(
        :severity, type: :score, instructions: "How severe?", criteria: %w[trivial minor major]
      )

      expect(question.to_payload).to eq(
        "type" => "score", "instructions" => "How severe?", "criteria" => %w[trivial minor major]
      )
    end

    it "rejects a single level, which is not a rubric" do
      expect { described_class.build(:s, type: :score, instructions: "?", criteria: ["only"]) }
        .to raise_error(Jevalyn::InvalidQuestionError, /between 2 and 10/)
    end

    it "rejects more than ten levels" do
      expect { described_class.build(:s, type: :score, instructions: "?", criteria: (1..11).map(&:to_s)) }
        .to raise_error(Jevalyn::InvalidQuestionError, /between 2 and 10/)
    end

    it "requires an array, not a hash" do
      expect { described_class.build(:s, type: :score, instructions: "?", criteria: { a: "b" }) }
        .to raise_error(Jevalyn::InvalidQuestionError, /ordered Array/)
    end
  end

  it "rejects an unknown type by name" do
    expect { described_class.build(:x, type: :vibes, instructions: "?") }
      .to raise_error(Jevalyn::InvalidQuestionError, /Jev supports :noul, :choice, :score/)
  end

  it "rejects empty instructions" do
    expect { described_class.build(:x, type: :noul, instructions: "  ") }
      .to raise_error(Jevalyn::InvalidQuestionError, /non-empty :instructions/)
  end

  it "accepts structured instructions, which the API allows" do
    question = described_class.build(:x, type: :noul, instructions: { "ask" => "Urgent?" })

    expect(question.to_payload["instructions"]).to eq("ask" => "Urgent?")
  end
end
