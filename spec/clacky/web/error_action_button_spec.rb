# frozen_string_literal: true

require "open3"

RSpec.describe "Web error card action button" do
  let(:web_dir) { File.expand_path("../../../lib/clacky/web", __dir__) }

  it "renders a check-account action for connection failures and keeps top-up for credit errors" do
    script = File.expand_path("../../support/error_action_button_test.js", __dir__)
    output, status = Open3.capture2e("node", script)
    expect(status.success?).to be(true), output
  end

  it "defines the check-account label in both locales" do
    i18n = File.read(File.join(web_dir, "i18n.js"))
    expect(i18n.scan(/"error\.check_account\.action":/).size).to eq(2)
  end

  it "tells the user what to check when retries are exhausted" do
    messages = Clacky::I18n.translations("llm.error.network_failed", retries: 10)
    expect(messages["zh"]).to include("暂时切换其他模型重试")
    expect(messages["zh"]).to include("检查账户余额")
    expect(messages["en"]).to match(/switch to another model and retry/i)
    expect(messages["en"]).to match(/check your account balance/i)
    expect(messages["zh"]).to include("10")
    expect(messages["en"]).to include("10")
  end

  it "carries the console url through the network-failure path" do
    caller = File.read(File.expand_path("../../../lib/clacky/agent/llm_caller.rb", __dir__))
    expect(caller).to include("action_url: @client.account_url")

    server = File.read(File.expand_path("../../../lib/clacky/server/http_server.rb", __dir__))
    expect(server).to match(/elsif e\.respond_to\?\(:action_url\) && e\.action_url/)
  end

  describe Clacky::AgentError do
    it "exposes an optional action url" do
      error = Clacky::AgentError.new("boom", raw_message: "Broken pipe", action_url: "https://example.com/keys")
      expect(error.action_url).to eq("https://example.com/keys")
      expect(error.raw_message).to eq("Broken pipe")
    end

    it "defaults to nil so existing callers are unaffected" do
      expect(Clacky::AgentError.new("boom").action_url).to be_nil
    end
  end

  describe Clacky::Client do
    it "resolves the account url from the provider preset" do
      client = Clacky::Client.new("sk-test", base_url: "https://api.openclacky.com",
                                             model: "auto", provider_id: "openclacky")
      expect(client.account_url).to eq("https://www.openclacky.com/llm_keys")
    end

    it "returns nil for a provider without a preset" do
      client = Clacky::Client.new("sk-test", base_url: "https://api.example.com/v1",
                                             model: "custom", provider_id: "nope")
      expect(client.account_url).to be_nil
    end
  end
end
