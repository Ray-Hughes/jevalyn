# frozen_string_literal: true

require "tmpdir"

RSpec.describe Jevalyn::Testing::Cassette do
  let(:url) { "https://api.typesafe.ai/v1/systemone" }
  let(:body) do
    JSON.generate(ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.92) }))
  end

  around do |example|
    Dir.mktmpdir { |dir| @dir = dir and example.run }
  end

  def path = File.join(@dir, "triage.json")

  def evaluate
    Jevalyn.client.evaluate(
      state: "payouts failing",
      questions: { urgent: { type: :noul, instructions: "Urgent?" } }
    )
  end

  it "records the first call and replays it afterwards" do
    stub_request(:post, url).to_return(status: 200, body: body,
                                       headers: { "Content-Type" => "application/json" })

    described_class.use(path) { evaluate }

    expect(a_request(:post, url)).to have_been_made.once
    expect(File).to exist(path)

    described_class.use(path) do
      expect(evaluate[:urgent]).to eq(0.92)
    end

    expect(a_request(:post, url)).to have_been_made.once
  end

  it "misses the cassette when the question changes, rather than replaying stale answers" do
    stub_request(:post, url).to_return(status: 200, body: body,
                                       headers: { "Content-Type" => "application/json" })

    described_class.use(path) { evaluate }
    described_class.use(path) do
      Jevalyn.client.evaluate(
        state: "payouts failing",
        questions: { urgent: { type: :noul, instructions: "Is this urgent, really?" } }
      )
    end

    expect(a_request(:post, url)).to have_been_made.twice
  end

  it "keys on content, not on the order a hash happened to be built in" do
    cassette = described_class.new(path)

    expect(cassette.digest_for({ "a" => 1, "b" => 2 })).to eq(cassette.digest_for({ "b" => 2, "a" => 1 }))
  end

  it "makes a bad cassette file obvious" do
    File.write(path, "not json")

    expect { described_class.new(path) }.to raise_error(Jevalyn::Error, /not valid JSON/)
  end
end
