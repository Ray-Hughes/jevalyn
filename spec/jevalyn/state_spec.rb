# frozen_string_literal: true

RSpec.describe Jevalyn::State do
  describe ".serialize" do
    it "passes a string straight through" do
      expect(described_class.serialize("a ticket")).to eq("a ticket")
    end

    it "stringifies hash keys, since the API takes JSON" do
      expect(described_class.serialize({ subject: "Payouts", body: "failing" }))
        .to eq("subject" => "Payouts", "body" => "failing")
    end

    it "handles nested structures" do
      state = described_class.serialize({ messages: [{ role: :user, text: "hi" }] })

      expect(state).to eq("messages" => [{ "role" => "user", "text" => "hi" }])
    end

    it "prefers #jevalyn_state when the object defines one" do
      object = Class.new do
        def jevalyn_state = { "only" => "what matters" }
        def as_json(*) = { "everything" => "including secrets" }
      end.new

      expect(described_class.serialize(object)).to eq("only" => "what matters")
    end

    it "falls back to #as_json" do
      object = Class.new do
        def as_json(*) = { "id" => 1 }
      end.new

      expect(described_class.serialize(object)).to eq("id" => 1)
    end

    it "refuses an empty state rather than paying for a pointless request" do
      [nil, "", {}, []].each do |empty|
        expect { described_class.serialize(empty) }
          .to raise_error(Jevalyn::ConfigurationError, /State is empty/)
      end
    end
  end

  describe ".estimated_tokens" do
    it "gives a rough count for sizing a request before sending it" do
      expect(described_class.estimated_tokens("a" * 400)).to eq(100)
    end
  end

  describe ".oversized?" do
    it "is false for a normal ticket" do
      expect(described_class.oversized?("a ticket body")).to be(false)
    end

    it "is true past Jev's 32k-token state budget" do
      expect(described_class.oversized?("a" * 200_000)).to be(true)
    end
  end
end

RSpec.describe Jevalyn::StateAdapters::ActiveRecordAdapter do
  # A stand-in for an ActiveRecord model: the adapter only needs #as_json.
  let(:record) do
    Class.new do
      def as_json(options = {})
        attributes = { "id" => 1, "email" => "a@example.com", "body" => "payouts failing",
                       "created_at" => "2026-09-19" }
        attributes = attributes.slice(*options[:only]) if options[:only]
        attributes = attributes.except(*options[:except]) if options[:except]
        attributes
      end
    end.new
  end

  it "sends every column by default" do
    expect(described_class.serialize(record).keys).to include("id", "email", "body", "created_at")
  end

  # Narrowing matters twice over: tokens cost money, and columns you did not need
  # should not leave the building.
  it "narrows to the columns a decision actually needs" do
    expect(described_class.serialize(record, only: %i[body])).to eq("body" => "payouts failing")
  end

  it "drops columns on request" do
    expect(described_class.serialize(record, except: %i[email])).not_to have_key("email")
  end
end
