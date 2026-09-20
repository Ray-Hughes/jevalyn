# frozen_string_literal: true

RSpec.describe Jevalyn::Guardrail do
  let(:url) { "https://api.typesafe.ai/v1/systemone" }

  def stub_noul(value)
    stub_request(:post, url).to_return(
      status: 200,
      body: JSON.generate(ResponseFixtures.systemone({ "safe_to_execute" => ResponseFixtures.noul(value) })),
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe ".check" do
    it "allows when the probability clears the gate" do
      stub_noul(0.97)

      result = ToolCallGuardrail.check({ "tool" => "read_file" })

      expect(result).to be_allow
      expect(result).not_to be_deny
      expect(result.probability).to eq(0.97)
      expect(result.threshold).to eq(0.9)
    end

    it "denies just under the gate" do
      stub_noul(0.89)

      expect(ToolCallGuardrail.check({ "tool" => "rm" })).to be_deny
    end

    it "allows exactly at the gate" do
      stub_noul(0.9)

      expect(ToolCallGuardrail.check({ "tool" => "shell", "command" => "rm -rf /" })).to be_allow
    end

    it "reads the gate at call time, so it can be changed after the class body ran" do
      stub_noul(0.5)
      strict = Class.new(ToolCallGuardrail)
      strict.allow_above 0.4

      expect(strict.check({ "tool" => "shell", "command" => "rm -rf /" })).to be_allow

      strict.allow_above 0.6
      expect(strict.check({ "tool" => "shell", "command" => "rm -rf /" })).to be_deny
    end
  end

  describe "when the API fails" do
    # A guardrail that fails open is worse than one that fails loudly.
    it "denies by default and records why" do
      stub_request(:post, url).to_return(status: 529, body: "{}")

      result = ToolCallGuardrail.check({ "tool" => "shell", "command" => "rm -rf /" })

      expect(result).to be_deny
      expect(result).to be_failed
      expect(result.error).to be_a(Jevalyn::OverloadedError)
    end

    it "denies on a timeout too" do
      stub_request(:post, url).to_timeout

      expect(ToolCallGuardrail.check({ "tool" => "shell", "command" => "rm -rf /" })).to be_deny
    end

    it "re-raises when told to" do
      stub_request(:post, url).to_return(status: 401, body: "{}")
      strict = Class.new(ToolCallGuardrail) { on_error :raise }

      expect { strict.check({ "tool" => "shell", "command" => "rm -rf /" }) }.to raise_error(Jevalyn::AuthenticationError)
    end

    it "is not marked failed on a normal denial" do
      stub_noul(0.1)

      expect(ToolCallGuardrail.check({ "tool" => "shell", "command" => "rm -rf /" })).not_to be_failed
    end
  end

  describe "class definition" do
    it "refuses more than one question" do
      klass = Class.new(described_class) do
        question :a, type: :noul, instructions: "?"
        question :b, type: :noul, instructions: "?"
      end

      expect { klass.check("x") }.to raise_error(Jevalyn::ConfigurationError, /exactly one question/)
    end

    it "refuses a non-noul question" do
      klass = Class.new(described_class) do
        question :a, type: :choice, instructions: "?", criteria: { x: "X", y: "Y" }
      end

      expect { klass.check("x") }.to raise_error(Jevalyn::ConfigurationError, /must be a :noul/)
    end

    it "rejects a gate outside 0..1" do
      expect { Class.new(described_class) { allow_above 2 } }
        .to raise_error(Jevalyn::ConfigurationError, /between 0 and 1/)
    end

    it "defaults to a coin flip, and says so in the constant" do
      expect(described_class::DEFAULT_ALLOW_ABOVE).to eq(0.5)
      expect(Class.new(described_class).allow_above).to eq(0.5)
    end
  end
end
