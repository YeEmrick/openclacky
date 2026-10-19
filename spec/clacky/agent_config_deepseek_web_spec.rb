# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Clacky::AgentConfig, "DeepSeek web tools credentials" do
  before do
    @dir = Dir.mktmpdir("clacky_agent_config_ds_web")
    stub_const("Clacky::SearchConfig::CONFIG_PATH", File.join(@dir, "search.yml"))
  end

  after { FileUtils.rm_rf(@dir) }

  def config_with(models)
    described_class.new(models: models)
  end

  def select_deepseek(key: "")
    Clacky::SearchConfig.save(provider: Clacky::SearchConfig::DEEPSEEK_WEB, key: key)
  end

  def deepseek_model(key = "sk-deepseek", base_url: "https://api.deepseek.com")
    {
      "model" => "deepseek-v4-pro", "api_key" => key, "base_url" => base_url,
      "provider_id" => "deepseekv4", "type" => "default"
    }
  end

  def openclacky_model(key: "clacky-abc", base_url: "https://api.openclacky.com")
    {
      "model" => "abs-claude-sonnet-5", "api_key" => key, "base_url" => base_url,
      "provider_id" => "openclacky", "type" => "default"
    }
  end

  describe "#deepseek_web_key" do
    it "prefers the key stored next to the DeepSeek provider selection" do
      select_deepseek(key: "dk-explicit")

      expect(config_with([deepseek_model]).deepseek_web_key).to eq("dk-explicit")
    end

    it "falls back to a DeepSeek model key" do
      select_deepseek

      expect(config_with([deepseek_model("sk-deepseek")]).deepseek_web_key).to eq("sk-deepseek")
    end

    it "falls back to an OpenClacky model key" do
      select_deepseek

      expect(config_with([openclacky_model(key: "clacky-abc")]).deepseek_web_key).to eq("clacky-abc")
    end

    it "prefers the model currently in use over earlier entries in the list" do
      select_deepseek
      deepseek = deepseek_model("sk-deepseek").merge("id" => "m-deepseek")
      openclacky = openclacky_model(key: "clacky-current").merge("id" => "m-openclacky")

      config = described_class.new(models: [deepseek, openclacky], current_model_id: "m-openclacky")

      expect(config.deepseek_web_key).to eq("clacky-current")
      expect(config.deepseek_web_base_url).to eq("https://api.openclacky.com")
    end

    it "falls back to another capable model when the one in use is not" do
      select_deepseek
      glm = { "model" => "glm-5.3", "api_key" => "glm-key", "base_url" => "https://open.bigmodel.cn/api/paas/v4", "id" => "m-glm" }
      deepseek = deepseek_model("sk-deepseek").merge("id" => "m-deepseek")

      config = described_class.new(models: [glm, deepseek], current_model_id: "m-glm")

      expect(config.deepseek_web_key).to eq("sk-deepseek")
    end

    it "is nil when no configured provider can run the hosted tools" do
      select_deepseek
      glm = { "model" => "glm-5.3", "api_key" => "glm-key", "base_url" => "https://open.bigmodel.cn/api/paas/v4" }

      expect(config_with([glm]).deepseek_web_key).to be_nil
    end

    it "ignores a model entry with a blank key" do
      select_deepseek

      expect(config_with([deepseek_model("")]).deepseek_web_key).to be_nil
    end

    it "ignores a key stored for a different provider" do
      Clacky::SearchConfig.save(provider: "tavily", key: "tvly-1")

      expect(config_with([deepseek_model("sk-deepseek")]).deepseek_web_key).to eq("sk-deepseek")
    end
  end

  describe "#deepseek_web_base_url" do
    it "routes to the OpenClacky gateway for an OpenClacky key" do
      key = "clacky-abc"
      config = config_with([openclacky_model(key: key, base_url: "https://api.openclacky.com/")])

      expect(config.deepseek_web_base_url(key)).to eq("https://api.openclacky.com")
    end

    it "routes a clacky- key to the public gateway when it is not a configured model" do
      config = config_with([deepseek_model])

      expect(config.deepseek_web_base_url("clacky-unlisted")).to eq("https://api.openclacky.com")
    end

    it "defaults to the DeepSeek API" do
      key = "sk-deepseek"
      config = config_with([deepseek_model(key)])

      expect(config.deepseek_web_base_url(key)).to eq("https://api.deepseek.com")
    end

    it "defaults to the DeepSeek API when no key resolves" do
      expect(config_with([]).deepseek_web_base_url).to eq("https://api.deepseek.com")
    end
  end

  describe "#deepseek_web_ready?" do
    it "is false while another provider is selected" do
      Clacky::SearchConfig.save(provider: "", key: "")
      config = config_with([deepseek_model])

      expect(config.deepseek_web_ready?).to be false
    end

    it "is false when DeepSeek is selected but no key resolves" do
      select_deepseek

      expect(config_with([]).deepseek_web_ready?).to be false
    end

    it "is true when DeepSeek is selected and a key resolves" do
      select_deepseek

      expect(config_with([deepseek_model]).deepseek_web_ready?).to be true
    end
  end
end
