# frozen_string_literal: true

RSpec.describe Jevalyn::Answer do
  def question(type, criteria = nil)
    Jevalyn::Question.build(:q, type: type, instructions: "?", criteria: criteria)
  end

  describe Jevalyn::Answer::Noul do
    subject(:answer) { question(:noul).build_answer("type" => "noul", "noul" => 0.92) }

    it "exposes the raw probability rather than rounding it to a boolean" do
      expect(answer.value).to eq(0.92)
    end

    # The spec this gem was written from assumed nouls carry a confidence. They do not
    # -- TypeSafe returns confidence only on Choice and Score answers.
    it "has no confidence, because the API returns none for a noul" do
      expect(answer.confidence).to be_nil
    end

    it "derives certainty from distance off a coin flip" do
      expect(answer.certainty).to eq(0.84)
      expect(question(:noul).build_answer("noul" => 0.5).certainty).to eq(0.0)
      expect(question(:noul).build_answer("noul" => 0.08).certainty).to eq(0.84)
    end

    it "lets the caller pick the cutoff" do
      expect(answer.true?).to be(true)
      expect(answer.true?(0.95)).to be(false)
      expect(answer.false?(0.95)).to be(true)
    end

    it "presents the implied two-way distribution" do
      expect(answer.probabilities).to eq("true" => 0.92, "false" => 0.08)
    end
  end

  describe Jevalyn::Answer::Choice do
    subject(:answer) do
      question(:choice, { billing: "a", technical: "b", sales: "c" }).build_answer(
        "type" => "choice", "choice" => "technical",
        "probabilities" => { "billing" => 0.08, "technical" => 0.85, "sales" => 0.07 },
        "confidence" => 0.82
      )
    end

    it "returns the winner as a symbol, matching how the criteria were written" do
      expect(answer.value).to eq(:technical)
      expect(answer.value_s).to eq("technical")
    end

    it "carries the API's confidence" do
      expect(answer.confidence).to eq(0.82)
      expect(answer.certainty).to eq(0.82)
    end

    it "ranks the options and names the runner-up" do
      expect(answer.ranked).to eq([[:technical, 0.85], [:billing, 0.08], [:sales, 0.07]])
      expect(answer.runner_up).to eq(:billing)
    end

    it "looks up the probability of any option" do
      expect(answer.probability_of(:billing)).to eq(0.08)
      expect(answer.probability_of("sales")).to eq(0.07)
    end
  end

  describe Jevalyn::Answer::Score do
    subject(:answer) do
      question(:score, ["Calm", "Frustrated", "Very angry"]).build_answer(
        "type" => "score", "score" => 1.6,
        "legend" => { "0" => "Calm", "1" => "Frustrated", "2" => "Very angry" },
        "probabilities" => { "0" => 0.05, "1" => 0.3, "2" => 0.65 },
        "confidence" => 0.78
      )
    end

    # The spec assumed a score came back as its level's label. It comes back as a
    # probability-weighted float that can land between levels.
    it "returns the weighted float the API sent" do
      expect(answer.value).to eq(1.6)
    end

    it "maps to the nearest level and its label" do
      expect(answer.level).to eq(2)
      expect(answer.label).to eq("Very angry")
    end

    it "reports the highest-probability level separately from the nearest one" do
      expect(answer.modal_level).to eq(2)
    end

    it "normalises across the declared levels for weighting in code" do
      expect(answer.normalized).to eq(0.8)
    end

    it "falls back to the declared criteria when the API sends no legend" do
      bare = question(:score, %w[low high]).build_answer("score" => 0.9)

      expect(bare.label).to eq("high")
    end
  end

  describe "#certain?" do
    it "is true when no threshold is set, since nothing was asked for" do
      expect(question(:noul).build_answer("noul" => 0.5).certain?(nil)).to be(true)
    end

    it "is false when the answer is missing entirely" do
      expect(question(:choice, { a: nil, b: nil }).build_answer(nil).certain?(0.5)).to be(false)
    end
  end
end
