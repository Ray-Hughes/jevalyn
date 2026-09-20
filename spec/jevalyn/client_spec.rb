# frozen_string_literal: true

RSpec.describe Jevalyn::Client do
  subject(:client) { described_class.new(Jevalyn.config) }

  let(:url) { "https://api.typesafe.ai/v1/systemone" }
  let(:questions) { { urgent: Jevalyn::Question.build(:urgent, type: :noul, instructions: "Urgent?") } }

  def stub_systemone(body:, status: 200, headers: {})
    stub_request(:post, url).to_return(
      status: status,
      body: JSON.generate(body),
      headers: { "Content-Type" => "application/json" }.merge(headers)
    )
  end

  describe "#evaluate" do
    it "sends the exact body the API documents" do
      stub_systemone(body: ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.92) }))

      client.evaluate(state: "Payouts failing", questions: questions)

      expect(a_request(:post, url).with(
               headers: { "Authorization" => "Bearer test-key", "Content-Type" => "application/json" },
               body: {
                 "model" => "jev-latest",
                 "state" => "Payouts failing",
                 "questions" => { "urgent" => { "type" => "noul", "instructions" => "Urgent?" } }
               }
             )).to have_been_made
    end

    it "sends a User-Agent naming the gem and version" do
      stub_systemone(body: ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.92) }))

      client.evaluate(state: "x", questions: questions)

      expect(a_request(:post, url).with(headers: { "User-Agent" => %r{\Ajevalyn/#{Jevalyn::VERSION} } }))
        .to have_been_made
    end

    it "returns a Result carrying the versioned model that answered" do
      stub_systemone(body: ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.92) },
                                                      model: "jev-1.13.0"))

      result = client.evaluate(state: "x", questions: questions)

      expect(result.model).to eq("jev-1.13.0")
      expect(result[:urgent]).to eq(0.92)
      expect(result.input_tokens).to eq(312)
    end

    it "accepts questions written as plain hashes" do
      stub_systemone(body: ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.1) }))

      result = client.evaluate(state: "x", questions: { urgent: { type: :noul, instructions: "Urgent?" } })

      expect(result[:urgent]).to eq(0.1)
    end

    it "honours a per-call model override" do
      stub_systemone(body: ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.5) }))

      client.evaluate(state: "x", questions: questions, model: "jev-1.13.0")

      expect(a_request(:post, url).with(body: hash_including("model" => "jev-1.13.0"))).to have_been_made
    end

    it "refuses an empty question set rather than sending a pointless request" do
      expect { client.evaluate(state: "x", questions: {}) }
        .to raise_error(Jevalyn::ConfigurationError, /non-empty Hash of questions/)
    end
  end

  describe "error mapping" do
    {
      401 => Jevalyn::AuthenticationError,
      403 => Jevalyn::PermissionDeniedError,
      404 => Jevalyn::NotFoundError,
      422 => Jevalyn::InvalidRequestError
    }.each do |status, error_class|
      it "raises #{error_class} on #{status}" do
        stub_systemone(status: status, body: { "error" => { "message" => "nope" } })

        expect { client.evaluate(state: "x", questions: questions) }
          .to raise_error(error_class, "nope")
      end
    end

    it "surfaces the status and body on the error" do
      stub_systemone(status: 422,
                     body: { "error" => { "message" => "questions.urgent: missing instructions" } })

      client.evaluate(state: "x", questions: questions)
    rescue Jevalyn::InvalidRequestError => e
      expect(e.status).to eq(422)
      expect(e.body).to eq("error" => { "message" => "questions.urgent: missing instructions" })
      expect(e).not_to be_retryable
    end

    it "raises TimeoutError rather than leaking Faraday's" do
      stub_request(:post, url).to_timeout

      expect { client.evaluate(state: "x", questions: questions) }
        .to raise_error(Jevalyn::TimeoutError, /timed out after/)
    end

    it "raises ConnectionError when the host is unreachable" do
      stub_request(:post, url).to_raise(Faraday::ConnectionFailed.new("refused"))

      expect { client.evaluate(state: "x", questions: questions) }
        .to raise_error(Jevalyn::ConnectionError, /Could not reach/)
    end
  end

  describe "retries" do
    it "retries a 429 and succeeds" do
      stub_request(:post, url)
        .to_return(status: 429, body: "{}", headers: { "Content-Type" => "application/json" })
        .then.to_return(
          status: 200,
          body: JSON.generate(ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.9) })),
          headers: { "Content-Type" => "application/json" }
        )

      result = client.evaluate(state: "x", questions: questions)

      expect(result[:urgent]).to eq(0.9)
      expect(a_request(:post, url)).to have_been_made.twice
    end

    it "retries a 529 overload" do
      stub_request(:post, url)
        .to_return(status: 529, body: "{}")
        .then.to_return(
          status: 200,
          body: JSON.generate(ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.3) })),
          headers: { "Content-Type" => "application/json" }
        )

      expect(client.evaluate(state: "x", questions: questions)[:urgent]).to eq(0.3)
    end

    it "gives up after max_retries and raises" do
      Jevalyn.config.max_retries = 1
      stub_systemone(status: 429, body: {})

      expect { client.evaluate(state: "x", questions: questions) }.to raise_error(Jevalyn::RateLimitError)
      expect(a_request(:post, url)).to have_been_made.twice
    end

    it "does not retry a 422, which will fail identically every time" do
      stub_systemone(status: 422, body: {})

      expect { client.evaluate(state: "x", questions: questions) }.to raise_error(Jevalyn::InvalidRequestError)
      expect(a_request(:post, url)).to have_been_made.once
    end

    it "waits for the API's retry-after when it sends one" do
      Jevalyn.config.retry_backoff = 99
      stub_request(:post, url)
        .to_return(status: 429, body: "{}", headers: { "Retry-After" => "0.01" })
        .then.to_return(
          status: 200,
          body: JSON.generate(ResponseFixtures.systemone({ "urgent" => ResponseFixtures.noul(0.1) })),
          headers: { "Content-Type" => "application/json" }
        )

      expect(client).to receive(:sleep).with(0.01)

      client.evaluate(state: "x", questions: questions)
    end
  end

  describe "#models" do
    it "lists the models the account may use" do
      stub_request(:get, "https://api.typesafe.ai/v1/models").to_return(
        status: 200,
        body: JSON.generate("models" => [{ "name" => "jev-latest" }]),
        headers: { "Content-Type" => "application/json" }
      )

      expect(client.models).to eq([{ "name" => "jev-latest" }])
    end
  end

  describe "without an API key" do
    it "says what to do instead of letting it become a 401" do
      Jevalyn.config.api_key = nil

      expect { client.evaluate(state: "x", questions: questions) }
        .to raise_error(Jevalyn::ConfigurationError, /TYPESAFE_API_KEY/)
    end
  end
end
