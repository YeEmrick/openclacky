# frozen_string_literal: true

require "json"

RSpec.describe Clacky::DeepSeekWebTools do
  def http_response(code, body)
    response = double("response", code: code.to_s, body: body)
    response
  end

  def stub_post(response)
    captured = {}
    http = double("http")
    allow(http).to receive(:request) do |req|
      captured[:uri] = req.path
      captured[:auth] = req["Authorization"]
      captured[:body] = JSON.parse(req.body)
      response
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)
    captured
  end

  describe ".search" do
    it "posts the query and maps results, preferring summary over snippet" do
      payload = {
        "results" => [
          {
            "title" => "Ruby 3.4",
            "url" => "https://example.com/ruby",
            "snippet" => "short",
            "summary" => "A much longer summary"
          },
          { "title" => "", "url" => "https://example.com/no-title", "snippet" => "only snippet" },
          { "title" => "no url", "url" => "" }
        ]
      }
      captured = stub_post(http_response(200, JSON.generate(payload)))

      results = described_class.search(query: "ruby", count: 3, api_key: "dk-1")

      expect(captured[:uri]).to eq("/v1/tools/search")
      expect(captured[:auth]).to eq("Bearer dk-1")
      expect(captured[:body]).to eq("query" => "ruby", "count" => 3)
      expect(results).to eq([
        { title: "Ruby 3.4", url: "https://example.com/ruby", snippet: "A much longer summary" },
        { title: "https://example.com/no-title", url: "https://example.com/no-title", snippet: "only snippet" }
      ])
    end

    it "clamps count into the documented 1..50 range" do
      captured = stub_post(http_response(200, '{"results":[]}'))

      described_class.search(query: "q", count: 99, api_key: "dk-1")
      expect(captured[:body]["count"]).to eq(50)

      described_class.search(query: "q", count: 0, api_key: "dk-1")
      expect(captured[:body]["count"]).to eq(1)
    end

    it "routes to the configured base url" do
      captured = {}
      http = double("http")
      allow(http).to receive(:request) do |req|
        captured[:host] = req["Host"]
        http_response(200, '{"results":[]}')
      end
      started = nil
      allow(Net::HTTP).to receive(:start) do |host, _port, **_opts, &blk|
        started = host
        blk.call(http)
      end

      described_class.search(query: "q", api_key: "clacky-1", base_url: "https://api.openclacky.com/")

      expect(started).to eq("api.openclacky.com")
    end

    it "raises with the upstream status on HTTP errors" do
      stub_post(http_response(401, '{"error":"bad key"}'))

      expect {
        described_class.search(query: "q", api_key: "dk-1")
      }.to raise_error(/HTTP 401.*bad key/)
    end

    it "retries once after a 429 and returns the later response" do
      http = double("http")
      allow(http).to receive(:request)
        .and_return(http_response(429, ""), http_response(200, '{"results":[]}'))
      allow(Net::HTTP).to receive(:start).and_yield(http)
      allow(described_class).to receive(:sleep)

      expect(described_class.search(query: "q", api_key: "dk-1")).to eq([])
      expect(http).to have_received(:request).twice
    end

    it "requires an api key" do
      expect {
        described_class.search(query: "q", api_key: "  ")
      }.to raise_error(ArgumentError, /API key/)
    end
  end

  describe ".fetch" do
    it "returns the rendered markdown and title" do
      captured = stub_post(http_response(200, JSON.generate(
        "title" => "Example",
        "content" => "\\#\\# Heading\n\n\\- item"
      )))

      result = described_class.fetch(url: "https://example.com", api_key: "dk-1")

      expect(captured[:uri]).to eq("/v1/tools/fetch")
      expect(captured[:body]).to eq("url" => "https://example.com")
      expect(result).to eq(title: "Example", content: "## Heading\n\n- item")
    end
  end

  describe ".clean_text" do
    it "unescapes markdown punctuation DeepSeek over-escapes" do
      expect(described_class.clean_text("\\# title \\_x\\_ \\[link\\]")).to eq("# title _x_ [link]")
    end

    it "leaves ordinary backslashes alone" do
      expect(described_class.clean_text("C:\\path")).to eq("C:\\path")
    end

    it "returns an empty string for nil" do
      expect(described_class.clean_text(nil)).to eq("")
    end
  end
end
