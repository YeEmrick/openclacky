# frozen_string_literal: true

require "spec_helper"

# The sessionbar stores "off" as an explicit "Default" choice. Agent used to
# collapse it to nil, which made the formatters unable to apply the per-model
# mapping for families whose provider default is the deepest level.
RSpec.describe Clacky::Agent, "reasoning effort hand-off to request formatters" do
  let(:messages) { [{ role: "user", content: "Hello" }] }

  def build_agent(effort = :unset)
    client = instance_double(Clacky::Client)
    client.instance_variable_set(:@api_key, "test-api-key")
    config = Clacky::AgentConfig.new(permission_mode: :auto_approve)
    config.add_model(
      model: "claude-sonnet-4.5",
      api_key: "test-api-key",
      base_url: "https://api.anthropic.com"
    )
    agent = described_class.new(
      client, config,
      working_dir: Dir.pwd, ui: nil, profile: "coding",
      session_id: Clacky::SessionManager.generate_id, source: :manual
    )
    agent.reasoning_effort = effort unless effort == :unset
    agent
  end

  def openai_body(agent, model)
    Clacky::MessageFormat::OpenAI.build_request_body(
      messages, model, [], 1024, false, reasoning_effort: agent.reasoning_effort
    )
  end

  def anthropic_body(agent, model)
    Clacky::MessageFormat::Anthropic.build_request_body(
      messages, model, [], 1024, false, reasoning_effort: agent.reasoning_effort
    )
  end

  describe "#reasoning_effort=" do
    %w[off OFF none disabled nothink].each do |value|
      it "keeps #{value.inspect} as an explicit default instead of nil" do
        expect(build_agent(value).reasoning_effort).to eq("off")
      end
    end

    it "keeps concrete levels untouched" do
      %w[low medium high xhigh max].each do |level|
        expect(build_agent(level).reasoning_effort).to eq(level)
      end
    end

    it "drops unset and unknown values" do
      [nil, "", "   ", "unsupported"].each do |value|
        expect(build_agent(value).reasoning_effort).to be_nil
      end
    end

    it "starts a fresh session at the Default choice" do
      expect(build_agent.reasoning_effort).to eq("off")
    end
  end

  describe "MiniMax M3.1-Flash" do
    it "uses the lightest effort for the Default choice" do
      agent = build_agent

      expect(anthropic_body(agent, "MiniMax-M3.1-Flash")[:output_config]).to eq(effort: "low")
      expect(openai_body(agent, "MiniMax-M3.1-Flash")[:reasoning_effort]).to eq("low")
    end

    it "leaves the provider default alone when no choice was ever made" do
      agent = build_agent(nil)

      expect(anthropic_body(agent, "MiniMax-M3.1-Flash").keys & %i[thinking output_config]).to be_empty
      expect(openai_body(agent, "MiniMax-M3.1-Flash").keys & %i[thinking reasoning_effort]).to be_empty
    end
  end

  describe "MiniMax M3" do
    it "disables thinking for the Default choice" do
      agent = build_agent("off")

      expect(anthropic_body(agent, "MiniMax-M3")[:thinking]).to eq(type: "disabled")
      expect(openai_body(agent, "MiniMax-M3")[:thinking]).to eq(type: "disabled")
    end
  end

  describe "models without an off mapping" do
    it "never forwards off-like values verbatim" do
      agent = build_agent("off")

      expect(openai_body(agent, "gpt-5")).not_to have_key(:reasoning_effort)
      expect(openai_body(agent, "deepseek-v4")).not_to have_key(:reasoning_effort)
    end
  end
end
