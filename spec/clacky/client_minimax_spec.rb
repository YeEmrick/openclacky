# frozen_string_literal: true

require "spec_helper"
require "clacky/client"

RSpec.describe Clacky::Client, "MiniMax serialized requests" do
  let(:messages) { [{ role: "user", content: "Hello" }] }

  # Exercise both public request entrypoints through JSON serialization at the
  # HTTP boundary. Only the network connection is replaced; routing, model IDs,
  # and request formatters are the production implementations.
  def capture_request(model:, effort:, api:, simple: false, base_url: nil, request_messages: messages)
    anthropic = api == "anthropic"
    base_url ||= anthropic ? "https://api.minimax.io/anthropic" : "https://api.minimax.io/v1"
    client = described_class.new("test-key", base_url: base_url, api_format: anthropic ? "anthropic-messages" : api, model: model)
    response_body = if anthropic
                      { content: [{ type: "text", text: "ok" }], stop_reason: "end_turn", usage: {} }
                    else
                      { choices: [{ message: { role: "assistant", content: "ok" }, finish_reason: "stop" }], usage: {} }
                    end
    response = instance_double(Faraday::Response, status: 200, headers: {}, body: response_body.to_json)
    connection = instance_double(Faraday::Connection)
    allow(client).to receive(anthropic ? :anthropic_connection : :openai_connection).and_return(connection)
    captured = nil
    allow(connection).to receive(:post) do |path, &block|
      expect(path).to end_with(anthropic ? "messages" : "chat/completions")
      request = Struct.new(:body).new
      block.call(request)
      captured = JSON.parse(request.body)
      response
    end

    if simple
      client.send_messages(request_messages, model: model, max_tokens: 1024, reasoning_effort: effort)
    else
      client.send_messages_with_tools(request_messages, model: model, tools: [], max_tokens: 1024, reasoning_effort: effort)
    end
    expect(captured.fetch("model")).to eq(model)
    captured
  end

  %w[openai-completions anthropic].each do |api|
    [false, true].each do |simple|
      context "#{api}, #{simple ? 'simple' : 'agent'} request" do
        %w[low medium high xhigh max].each do |effort|
          it "serializes Flash #{effort} in the transport-specific effort field" do
            body = capture_request(model: "MiniMax-M3.1-Flash", effort: effort, api: api, simple: simple)
            if api == "anthropic"
              expect(body["output_config"]).to eq("effort" => effort)
              expect(body).not_to have_key("reasoning_effort")
            else
              expect(body["reasoning_effort"]).to eq(effort)
              expect(body).not_to have_key("output_config")
            end
            expect(body).not_to have_key("thinking")
          end
        end

        %w[off nothink disabled none].each do |effort|
          it "maps Flash #{effort} to low without disabling thinking" do
            body = capture_request(model: "MiniMax-M3.1-Flash", effort: effort, api: api, simple: simple)
            actual = api == "anthropic" ? body.dig("output_config", "effort") : body["reasoning_effort"]
            expect(actual).to eq("low")
            expect(body).not_to have_key("thinking")
          end

          it "explicitly disables M3 thinking for #{effort}" do
            body = capture_request(model: "MiniMax-M3", effort: effort, api: api, simple: simple)
            expect(body["thinking"]).to eq("type" => "disabled")
            expect(body.keys & %w[reasoning_effort output_config]).to be_empty
          end
        end

        [nil, "", "on", "unsupported"].each do |effort|
          it "leaves Flash effort to the provider for #{effort.inspect}" do
            body = capture_request(model: "MiniMax-M3.1-Flash", effort: effort, api: api, simple: simple)
            expect(body.keys & %w[thinking reasoning_effort output_config]).to be_empty
          end
        end

        it "keeps M3's provider default when effort is omitted" do
          body = capture_request(model: "MiniMax-M3", effort: nil, api: api, simple: simple)
          expect(body.keys & %w[thinking reasoning_effort output_config]).to be_empty
        end

        it "enables M3 adaptive thinking without sending ignored effort" do
          body = capture_request(model: "MiniMax-M3", effort: "high", api: api, simple: simple)
          expect(body["thinking"]).to eq("type" => "adaptive")
          expect(body.keys & %w[reasoning_effort output_config]).to be_empty
        end

        %w[MiniMax-M2.7 MiniMax-M2.5 saved-custom-model].each do |model|
          it "preserves explicitly selected #{model}" do
            capture_request(model: model, effort: nil, api: api, simple: simple)
          end
        end
      end
    end
  end

  %w[api.minimax.io api.minimaxi.com].each do |host|
    %w[openai-completions anthropic].each do |api|
      it "sends the preset default with preserved image content through #{host} #{api}" do
        model = Clacky::Providers.default_model("minimax")
        expect(model).to eq("MiniMax-M3.1-Flash")
        image_messages = [{ role: "user", content: [
          { type: "text", text: "Describe this image" },
          { type: "image_url", image_url: { url: "data:image/png;base64,aGVsbG8=" } }
        ] }]
        path = api == "anthropic" ? "anthropic" : "v1"
        body = capture_request(model: model, effort: nil, api: api, base_url: "https://#{host}/#{path}", request_messages: image_messages)
        expect(body["messages"].to_json).to include("aGVsbG8=")
        expect(body.keys & %w[thinking reasoning_effort output_config service_tier reasoning_split]).to be_empty
      end
    end
  end

  it "preserves the gateway's M3 id and explicit legacy id" do
    %w[minimax-m3 minimax-m2.7].each do |model|
      capture_request(model: model, effort: nil, api: "openai-completions", base_url: "https://ollama.com")
    end
  end

  it "does not apply MiniMax rules to unrelated OpenAI models" do
    body = capture_request(model: "gpt-5", effort: "high", api: "openai-completions")
    expect(body["reasoning_effort"]).to eq("high")
  end

  it "preserves Claude adaptive effort" do
    body = capture_request(model: "claude-sonnet-4-6", effort: "high", api: "anthropic")
    expect(body["thinking"]).to eq("type" => "adaptive")
    expect(body["output_config"]).to eq("effort" => "high")
  end
end
