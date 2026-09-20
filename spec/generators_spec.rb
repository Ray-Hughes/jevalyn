# frozen_string_literal: true

require "rails/generators"
require "tmpdir"
require "generators/jevalyn/install/install_generator"
require "generators/jevalyn/decision/decision_generator"
require "generators/jevalyn/guardrail/guardrail_generator"

# Generated code is the first thing anyone sees. A template that no longer matches the
# DSL is a broken first impression, so the templates are run and loaded here rather
# than only eyeballed.
RSpec.describe "generators", :aggregate_failures do # rubocop:disable RSpec/DescribeClass
  around do |example|
    Dir.mktmpdir { |dir| @dest = dir and example.run }
  end

  def generate(klass, args = [])
    klass.start(args, destination_root: @dest, behavior: :invoke, shell: Thor::Shell::Basic.new)
  end

  def read(path) = File.read(File.join(@dest, path))

  def exist?(path) = File.exist?(File.join(@dest, path))

  describe "jevalyn:install" do
    before { generate(Jevalyn::Generators::InstallGenerator) }

    it "writes an initializer that configures the gem" do
      expect(read("config/initializers/jevalyn.rb")).to include("Jevalyn.configure", "TYPESAFE_API_KEY")
    end

    it "turns mock mode on for the test environment" do
      expect(read("config/initializers/jevalyn.rb")).to include("c.mock_mode = Rails.env.test?")
    end

    it "creates somewhere for decisions to live" do
      expect(exist?("app/decisions/.keep")).to be(true)
    end

    it "honours a different key variable" do
      Dir.mktmpdir do |other|
        Jevalyn::Generators::InstallGenerator.start(
          ["--api-key-env", "JEV_KEY"], destination_root: other, shell: Thor::Shell::Basic.new
        )

        expect(File.read(File.join(other, "config/initializers/jevalyn.rb"))).to include('ENV["JEV_KEY"]')
      end
    end
  end

  describe "jevalyn:decision" do
    it "generates a class declaring every question it was asked for" do
      generate(Jevalyn::Generators::DecisionGenerator,
               %w[InboundTriage urgent:noul department:choice severity:score])
      load File.join(@dest, "app/decisions/inbound_triage.rb")

      expect(InboundTriage.question_names).to eq(%i[urgent department severity])
      expect(InboundTriage.questions.values.map(&:type)).to eq(%i[noul choice score])
      expect(InboundTriage.confidence_threshold).to eq(0.75)
    ensure
      Object.send(:remove_const, :InboundTriage) if defined?(InboundTriage)
    end

    it "produces a file that loads and answers under a stub" do
      generate(Jevalyn::Generators::DecisionGenerator, %w[OrderCheck flagged:noul])
      load File.join(@dest, "app/decisions/order_check.rb")

      Jevalyn.config.mock_mode = true
      Jevalyn::Testing.stub(OrderCheck, flagged: true)

      expect(OrderCheck.evaluate("an order").flagged?).to be(true)
    ensure
      Object.send(:remove_const, :OrderCheck) if defined?(OrderCheck)
    end

    it "generates a spec alongside" do
      generate(Jevalyn::Generators::DecisionGenerator, %w[InboundTriage urgent:noul])

      expect(read("spec/decisions/inbound_triage_spec.rb")).to include("RSpec.describe InboundTriage")
    end

    it "can skip the spec" do
      generate(Jevalyn::Generators::DecisionGenerator, ["InboundTriage", "--no-spec"])

      expect(exist?("spec/decisions/inbound_triage_spec.rb")).to be(false)
    end

    # Thor's .start swallows errors into a printed message, so drive the generator
    # directly to see the exception a developer would actually get told about.
    it "rejects a question type Jev does not have" do
      generator = Jevalyn::Generators::DecisionGenerator.new(
        %w[Bad mood:vibes], [], destination_root: @dest, shell: Thor::Shell::Basic.new
      )

      expect { generator.invoke_all }.to raise_error(Thor::Error, /Jev has three/)
    end
  end

  describe "jevalyn:guardrail" do
    it "produces a guardrail that gates at the requested probability" do
      generate(Jevalyn::Generators::GuardrailGenerator, ["ToolCall", "--allow-above", "0.95"])
      load File.join(@dest, "app/decisions/tool_call.rb")

      Jevalyn.config.mock_mode = true
      Jevalyn::Testing.stub(ToolCall, safe: 0.96)

      expect(ToolCall.allow_above).to eq(0.95)
      expect(ToolCall.check("a tool call")).to be_allow
    ensure
      Object.send(:remove_const, :ToolCall) if defined?(ToolCall)
    end

    it "names the question when asked to" do
      generate(Jevalyn::Generators::GuardrailGenerator, %w[Publish --question publishable])

      expect(read("app/decisions/publish.rb")).to include("question :publishable, type: :noul")
    end
  end
end
