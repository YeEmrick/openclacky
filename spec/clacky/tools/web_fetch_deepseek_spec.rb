# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe Clacky::Tools::WebFetch, "DeepSeek rendered page fetch" do
  let(:tool) { described_class.new }
  let(:config) do
    Clacky::AgentConfig.new(models: [
      {
        "model" => "deepseek-v4-pro", "api_key" => "sk-deepseek",
        "base_url" => "https://api.deepseek.com", "provider_id" => "deepseekv4", "type" => "default"
      }
    ])
  end

  before do
    @dir = Dir.mktmpdir("clacky_web_fetch_deepseek")
    stub_const("Clacky::SearchConfig::CONFIG_PATH", File.join(@dir, "search.yml"))
    Clacky::SearchConfig.save(provider: Clacky::SearchConfig::DEEPSEEK_WEB, key: "")
    tool.agent = double("agent", config: config)
  end

  after { FileUtils.rm_rf(@dir) }

  def rendered(content, title: "Rendered")
    { title: title, content: content }
  end

  it "fetches through DeepSeek without touching the local scraper" do
    allow(tool).to receive(:fetch_url)
    allow(Clacky::DeepSeekWebTools).to receive(:fetch).and_return(rendered("# Heading\n\nbody"))

    result = tool.execute(url: "https://example.com/post")

    expect(result[:error]).to be_nil
    expect(result[:title]).to eq("Rendered")
    expect(result[:content]).to eq("# Heading\n\nbody")
    expect(result[:content_type]).to eq("text/markdown")
    expect(Clacky::DeepSeekWebTools).to have_received(:fetch)
      .with(hash_including(api_key: "sk-deepseek", base_url: "https://api.deepseek.com", url: "https://example.com/post"))
    expect(tool).not_to have_received(:fetch_url)
  end

  it "spills oversized rendered content to a temp file" do
    allow(Clacky::DeepSeekWebTools).to receive(:fetch).and_return(rendered("x" * 900))

    result = tool.execute(url: "https://example.com/big", max_length: 100)

    expect(result[:truncated]).to be true
    expect(result[:content].length).to eq(100)
    expect(result[:temp_file]).to end_with(".md")
    expect(File.read(result[:temp_file]).length).to eq(900)
  end

  it "still validates the URL before calling DeepSeek" do
    allow(Clacky::DeepSeekWebTools).to receive(:fetch)

    result = tool.execute(url: "ftp://example.com/file")

    expect(result[:error]).to eq("URL must be HTTP or HTTPS")
    expect(Clacky::DeepSeekWebTools).not_to have_received(:fetch)
  end

  it "falls back to the local scraper when DeepSeek fails" do
    response = double("response", body: "<html><head><title>Local</title></head><body><p>hi</p></body></html>", code: "200")
    allow(response).to receive(:[]).with("content-type").and_return("text/html")
    allow(tool).to receive(:fetch_url).and_return(response)
    allow(Clacky::DeepSeekWebTools).to receive(:fetch).and_raise(StandardError.new("HTTP 500"))

    result = tool.execute(url: "https://example.com/post")

    expect(result[:title]).to eq("Local")
    expect(result[:error]).to be_nil
    expect(Clacky::DeepSeekWebTools).to be_cooling_down
  end

  it "skips DeepSeek during the cooldown after a failure" do
    response = double("response", body: "<html><head><title>Local</title></head><body><p>hi</p></body></html>", code: "200")
    allow(response).to receive(:[]).with("content-type").and_return("text/html")
    allow(tool).to receive(:fetch_url).and_return(response)
    allow(Clacky::DeepSeekWebTools).to receive(:fetch).and_raise(StandardError.new("HTTP 500"))
    tool.execute(url: "https://example.com/post")

    tool.execute(url: "https://example.com/next")

    expect(Clacky::DeepSeekWebTools).to have_received(:fetch).once
  end

  it "reports the DeepSeek error when the local scraper fails too" do
    allow(tool).to receive(:fetch_url).and_raise(StandardError.new("local boom"))
    allow(Clacky::DeepSeekWebTools).to receive(:fetch).and_raise(StandardError.new("HTTP 500"))

    result = tool.execute(url: "https://example.com/post")

    expect(result[:error]).to include("local boom")
    expect(result[:error]).to include("HTTP 500")
  end

  it "keeps the local scraper while another provider is selected" do
    Clacky::SearchConfig.save(provider: "")
    response = double("response", body: "<html><head><title>Local</title></head><body><p>hi</p></body></html>", code: "200")
    allow(response).to receive(:[]).with("content-type").and_return("text/html")
    allow(tool).to receive(:fetch_url).and_return(response)
    allow(Clacky::DeepSeekWebTools).to receive(:fetch)

    result = tool.execute(url: "https://example.com/post")

    expect(result[:title]).to eq("Local")
    expect(Clacky::DeepSeekWebTools).not_to have_received(:fetch)
  end
end
