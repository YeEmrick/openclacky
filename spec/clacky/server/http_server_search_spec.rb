# frozen_string_literal: true

require "spec_helper"
require "json"
require "tmpdir"
require "fileutils"
require "clacky/server/http_server"
require "clacky/agent_config"

require_relative "../../support/http_server_spec_helpers"

RSpec.describe Clacky::Server::HttpServer, "search routes" do
  include HttpServerSpecHelpers

  let(:agent_config) do
    Clacky::AgentConfig.new(models: [
      { "model" => "m", "api_key" => "k", "base_url" => "https://example.invalid/v1", "type" => "default" }
    ])
  end

  before do
    @dir = Dir.mktmpdir("clacky_http_search_spec")
    FileUtils.mkdir_p(File.join(@dir, "searchers"))
    stub_const("Clacky::SearchConfig::CONFIG_PATH", File.join(@dir, "search.yml"))
    stub_const("Clacky::Utils::SearcherManager::SEARCHERS_DIR", File.join(@dir, "searchers"))
  end

  after { FileUtils.rm_rf(@dir) }

  def install_searcher(name, body)
    File.write(File.join(@dir, "searchers", "#{name}.rb"), body)
  end

  def call(method, path, body = nil, config: agent_config)
    with_server(agent_config: config) do |server|
      req = fake_req(method: method, path: path, body: body)
      res = fake_res
      dispatch(server, req, res)
      [res.status, parsed_body(res)]
    end
  end

  describe "GET /api/config/search" do
    it "suggests the free chain when no model can serve DeepSeek web tools" do
      install_searcher("tavily", "puts '[]'")

      status, body = call("GET", "/api/config/search")

      expect(status).to eq(200)
      expect(body["provider"]).to eq("")
      expect(body["key_masked"]).to be_nil
      expect(body["available"]).to eq(["tavily"])
    end

    it "suggests DeepSeek when a configured DeepSeek model carries a key" do
      config = Clacky::AgentConfig.new(models: [
        { "model" => "deepseek-v4-pro", "provider_id" => "deepseekv4",
          "api_key" => "sk-deepseek", "base_url" => "https://api.deepseek.com/v1",
          "type" => "default" }
      ])

      _status, body = call("GET", "/api/config/search", config: config)

      expect(body["provider"]).to eq("deepseek_web")
    end

    it "suggests DeepSeek when a configured OpenClacky model carries a key" do
      config = Clacky::AgentConfig.new(models: [
        { "model" => "glm-4.6", "provider_id" => "openclacky",
          "api_key" => "clacky-abc", "base_url" => "https://api.openclacky.com/v1",
          "type" => "default" }
      ])

      _status, body = call("GET", "/api/config/search", config: config)

      expect(body["provider"]).to eq("deepseek_web")
    end

    it "honours an explicit choice once search.yml exists" do
      Clacky::SearchConfig.save(provider: "", key: "")
      config = Clacky::AgentConfig.new(models: [
        { "model" => "deepseek-v4-pro", "provider_id" => "deepseekv4",
          "api_key" => "sk-deepseek", "base_url" => "https://api.deepseek.com/v1",
          "type" => "default" }
      ])

      _status, body = call("GET", "/api/config/search", config: config)

      expect(body["provider"]).to eq("")
    end

    it "masks the stored key" do
      install_searcher("tavily", "puts '[]'")
      Clacky::SearchConfig.save(provider: "tavily", key: "tvly-abcdefghijklmnop")

      _status, body = call("GET", "/api/config/search")

      expect(body["provider"]).to eq("tavily")
      expect(body["key_masked"]).to include("****")
      expect(body["key_masked"]).not_to include("abcdefghijklmnop")
    end
  end

  describe "PATCH /api/config/search" do
    it "saves provider and key" do
      install_searcher("tavily", "puts '[]'")

      status, body = call("PATCH", "/api/config/search", { provider: "tavily", key: "k1" })

      expect(status).to eq(200)
      expect(body["ok"]).to be true
      expect(Clacky::SearchConfig.load).to include("provider" => "tavily", "key" => "k1")
    end

    it "accepts the bundled DeepSeek provider without an installed script" do
      install_searcher("tavily", "puts '[]'")

      status, body = call("PATCH", "/api/config/search",
                          { provider: "deepseek_web", key: "" })

      expect(status).to eq(200)
      expect(body["provider"]).to eq("deepseek_web")
      expect(Clacky::SearchConfig.deepseek_web?).to be true
      expect(Clacky::SearchConfig.script_path).to be_nil
    end

    it "rejects an unknown provider" do
      status, body = call("PATCH", "/api/config/search", { provider: "ghost" })

      expect(status).to eq(422)
      expect(body["error"]).to include("Unknown search provider")
    end

    it "accepts a blank provider to fall back to the built-in engines" do
      install_searcher("tavily", "puts '[]'")
      Clacky::SearchConfig.save(provider: "tavily", key: "k1")

      status, _body = call("PATCH", "/api/config/search", { provider: "" })

      expect(status).to eq(200)
      expect(Clacky::SearchConfig.load["provider"]).to eq("")
    end

    it "keeps the stored key when the masked value is sent back" do
      install_searcher("tavily", "puts '[]'")
      Clacky::SearchConfig.save(provider: "tavily", key: "tvly-original")

      call("PATCH", "/api/config/search", { provider: "tavily", key: "tvly-ori****inal" })

      expect(Clacky::SearchConfig.load["key"]).to eq("tvly-original")
    end

    it "rejects a script searcher with no API key" do
      install_searcher("tavily", "puts '[]'")

      status, body = call("PATCH", "/api/config/search", { provider: "tavily", key: "" })

      expect(status).to eq(422)
      expect(body["error"]).to include("API key is required")
      expect(Clacky::SearchConfig.load["provider"]).not_to eq("tavily")
    end

    it "rejects switching to a script searcher while the stored key is blank" do
      install_searcher("tavily", "puts '[]'")
      Clacky::SearchConfig.save(provider: "", key: "")

      status, body = call("PATCH", "/api/config/search", { provider: "tavily" })

      expect(status).to eq(422)
      expect(body["error"]).to include("API key is required")
    end
  end

  describe "POST /api/config/search/test" do
    it "reports success with the result count" do
      install_searcher("tavily", <<~RUBY)
        require "json"
        puts JSON.generate([{ "title" => "t", "url" => "https://example.com" }])
      RUBY

      status, body = call("POST", "/api/config/search/test", { provider: "tavily", key: "k1" })

      expect(status).to eq(200)
      expect(body["ok"]).to be true
      expect(body["message"]).to include("1 result")
    end

    it "surfaces the searcher's error message" do
      install_searcher("tavily", "warn 'Tavily API key is not configured'\nexit 1\n")

      _status, body = call("POST", "/api/config/search/test", { provider: "tavily", key: "bad" })

      expect(body["ok"]).to be false
      expect(body["message"]).to include("not configured")
    end

    it "fails when the searcher is not installed" do
      _status, body = call("POST", "/api/config/search/test", { provider: "ghost" })

      expect(body["ok"]).to be false
      expect(body["message"]).to include("not found")
    end

    it "fails when the searcher does not output a JSON array" do
      install_searcher("tavily", "puts 'nope'\n")

      _status, body = call("POST", "/api/config/search/test", { provider: "tavily", key: "k" })

      expect(body["ok"]).to be false
      expect(body["message"]).to include("JSON array")
    end

    it "tests the bundled DeepSeek provider without a script" do
      allow(Clacky::DeepSeekWebTools).to receive(:search)
        .and_return([{ title: "t", url: "https://example.com", snippet: "s" }])

      status, body = call("POST", "/api/config/search/test",
                          { provider: "deepseek_web", key: "dk-1" })

      expect(status).to eq(200)
      expect(body["ok"]).to be true
      expect(body["message"]).to include("1 result")
      expect(Clacky::DeepSeekWebTools).to have_received(:search)
        .with(hash_including(api_key: "dk-1"))
    end

    it "asks for a DeepSeek key when none can be resolved" do
      _status, body = call("POST", "/api/config/search/test",
                           { provider: "deepseek_web", key: "" })

      expect(body["ok"]).to be false
      expect(body["message"]).to include("No DeepSeek key")
    end
  end
end
