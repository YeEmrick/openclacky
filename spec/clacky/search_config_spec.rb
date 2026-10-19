# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Clacky::SearchConfig do
  before do
    @dir = Dir.mktmpdir("clacky_search_config")
    stub_const("Clacky::SearchConfig::CONFIG_PATH", File.join(@dir, "search.yml"))
    Clacky::DeepSeekWebTools.reset_cooldown!
  end

  after { FileUtils.rm_rf(@dir) }

  describe ".load" do
    it "defaults to DeepSeek's hosted tools when no config exists" do
      expect(described_class.load).to eq("provider" => "deepseek_web", "key" => "")
    end

    it "keeps a blank provider, which means built-in engines only" do
      described_class.save(provider: "", key: "")

      expect(described_class.load["provider"]).to eq("")
      expect(described_class.deepseek_web?).to be false
    end

    it "reads provider and key" do
      File.write(described_class::CONFIG_PATH, { "provider" => "tavily", "key" => "tvly-1" }.to_yaml)

      config = described_class.load
      expect(config["provider"]).to eq("tavily")
      expect(config["key"]).to eq("tvly-1")
    end

    it "tolerates malformed YAML instead of raising" do
      File.write(described_class::CONFIG_PATH, "provider: [unclosed")

      expect(described_class.load["provider"]).to eq("deepseek_web")
    end

    it "tolerates a non-Hash document" do
      File.write(described_class::CONFIG_PATH, "- just\n- a list\n")

      expect(described_class.load["key"]).to eq("")
    end
  end

  describe ".configured?" do
    it "is false when no config file exists" do
      expect(described_class.configured?).to be false
    end

    it "is true after an explicit blank provider is saved" do
      described_class.save(provider: "", key: "")

      expect(described_class.configured?).to be true
    end

    it "is false when the file has no provider key" do
      File.write(described_class::CONFIG_PATH, { "key" => "tvly-1" }.to_yaml)

      expect(described_class.configured?).to be false
    end

    it "is false for malformed YAML" do
      File.write(described_class::CONFIG_PATH, "provider: [unclosed")

      expect(described_class.configured?).to be false
    end
  end

  describe ".save" do
    it "persists values and restricts file permissions" do
      described_class.save(provider: "tavily", key: "tvly-1")

      expect(described_class.load).to eq("provider" => "tavily", "key" => "tvly-1")
      expect(File.stat(described_class::CONFIG_PATH).mode & 0o777).to eq(0o600)
    end

    it "keeps omitted fields untouched" do
      described_class.save(provider: "tavily", key: "tvly-1")
      described_class.save(key: "tvly-2")

      expect(described_class.load).to eq("provider" => "tavily", "key" => "tvly-2")
    end

    it "clears a DeepSeek cooldown so a new setting takes effect immediately" do
      Clacky::DeepSeekWebTools.mark_unavailable!
      expect(Clacky::DeepSeekWebTools).to be_cooling_down

      described_class.save(provider: "tavily", key: "tvly-1")

      expect(Clacky::DeepSeekWebTools).not_to be_cooling_down
    end
  end

  describe ".deepseek_web?" do
    it "is true only when DeepSeek is the selected provider" do
      described_class.save(provider: described_class::DEEPSEEK_WEB, key: "")
      expect(described_class.deepseek_web?).to be true

      described_class.save(provider: "tavily")
      expect(described_class.deepseek_web?).to be false

      described_class.save(provider: "")
      expect(described_class.deepseek_web?).to be false
    end
  end

  describe ".script_path" do
    it "is nil while the default DeepSeek provider is in effect" do
      expect(described_class.script_path).to be_nil
    end

    it "is nil for the bundled DeepSeek provider, which has no script" do
      described_class.save(provider: described_class::DEEPSEEK_WEB)

      expect(described_class.script_path).to be_nil
    end

    it "resolves a configured provider to its installed script" do
      Dir.mktmpdir do |searchers|
        stub_const("Clacky::Utils::SearcherManager::SEARCHERS_DIR", searchers)
        File.write(File.join(searchers, "mine.rb"), "# searcher\n")
        allow(Clacky::Utils::SearcherManager).to receive(:available).and_return(["mine"])
        allow(Clacky::Utils::SearcherManager).to receive(:path_for) do |name|
          path = File.join(searchers, "#{name}.rb")
          File.exist?(path) ? path : nil
        end
        described_class.save(provider: "mine")

        expect(described_class.script_path).to eq(File.join(searchers, "mine.rb"))
      end
    end

    it "is nil when the configured provider is not installed" do
      allow(Clacky::Utils::SearcherManager).to receive(:path_for).and_return(nil)
      described_class.save(provider: "ghost")

      expect(described_class.script_path).to be_nil
    end
  end
end
