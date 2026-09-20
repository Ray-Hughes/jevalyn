# frozen_string_literal: true

RSpec.describe Jevalyn::Result do
  subject(:result) do
    described_class.new(
      questions: questions,
      raw: ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.92) })
    )
  end

  let(:questions) do
    { urgent: Jevalyn::Question.build(:urgent, type: :noul, instructions: "?") }
  end

  it "reads an answer by name" do
    expect(result[:urgent]).to eq(0.92)
    expect(result[:urgent]).to eq(result["urgent"])
  end

  it "names the questions it has when asked for one it does not" do
    expect { result[:missing] }
      .to raise_error(Jevalyn::UnknownQuestionError, /No answer named :missing.*:urgent/m)
  end

  it "reports usage" do
    expect(result.input_tokens).to eq(312)
    expect(result.output_tokens).to eq(48)
  end

  it "survives a response with no usage block" do
    bare = described_class.new(questions: questions, raw: { "answers" => {} })

    expect(bare.input_tokens).to eq(0)
    expect(bare[:urgent]).to be_nil
  end

  it "is enumerable over name/answer pairs" do
    expect(result.map { |name, answer| [name, answer.class] }).to eq([[:urgent, Jevalyn::Answer::Noul]])
  end

  it "is certain when no threshold was asked for" do
    expect(result).to be_certain
  end

  it "reports the lowest certainty across answers" do
    expect(result.min_certainty).to eq(0.84)
  end
end
