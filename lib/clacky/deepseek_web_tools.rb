# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module Clacky
  # Client for DeepSeek hosted web tools:
  #   POST /v1/tools/search
  #   POST /v1/tools/fetch
  #
  # DeepSeek charges per successful request (CNY 5 / 1000 calls).
  # Handles endpoint routing, auth header, request formatting, rate-limit (429)
  # backoff, and cleans up DeepSeek-specific Markdown escapes (\# \- \_).
  module DeepSeekWebTools
    DEFAULT_BASE_URL = "https://api.deepseek.com"
    SEARCH_TIMEOUT = 30
    FETCH_TIMEOUT  = 45
    MAX_RETRIES    = 2

    # A failed call (bad key, empty balance, outage) keeps failing, and each
    # attempt costs a timeout on the user's critical path. Once one fails, stay
    # off DeepSeek and let the free engines serve until it expires.
    # The window is owned by WebSearch so hosted and free providers share it.

    class << self
      # True while DeepSeek should be skipped after a recent failure.
      def cooling_down?
        until_at = @cooldown_until
        return false if until_at.nil?

        Time.now < until_at
      end

      def mark_unavailable!
        @cooldown_until = Time.now + Clacky::Tools::WebSearch::PROVIDER_COOLDOWN_SECONDS
      end

      def reset_cooldown!
        @cooldown_until = nil
      end
      # Perform web search via DeepSeek.
      # @param query [String]
      # @param count [Integer] results count (1..50)
      # @param api_key [String]
      # @param base_url [String]
      # @return [Array<Hash>] [{ title:, url:, snippet: }]
      def search(query:, count: 10, api_key:, base_url: DEFAULT_BASE_URL)
        payload = {
          "query" => query.to_s,
          "count" => [[count.to_i, 1].max, 50].min
        }
        res = post_with_retry(
          path: "/v1/tools/search",
          payload: payload,
          api_key: api_key,
          base_url: base_url,
          timeout: SEARCH_TIMEOUT
        )
        data = JSON.parse(res.body) rescue {}
        raw_results = data["results"] || []

        raw_results.filter_map do |item|
          url = item["url"].to_s.strip
          next if url.empty?

          title = clean_text(item["title"].to_s.strip)
          title = url if title.empty?

          # Prefer summary (400-800 chars rich text), fall back to snippet
          summary = item["summary"].to_s.strip
          snippet = summary.empty? ? item["snippet"].to_s.strip : summary
          snippet = clean_text(snippet)[0, 400]

          {
            title: title,
            url: url,
            snippet: snippet
          }
        end
      end

      # Fetch web page content rendered as Markdown via DeepSeek.
      # @param url [String]
      # @param api_key [String]
      # @param base_url [String]
      # @return [Hash] { title:, content: }
      def fetch(url:, api_key:, base_url: DEFAULT_BASE_URL)
        payload = { "url" => url.to_s }
        res = post_with_retry(
          path: "/v1/tools/fetch",
          payload: payload,
          api_key: api_key,
          base_url: base_url,
          timeout: FETCH_TIMEOUT
        )
        data = JSON.parse(res.body) rescue {}
        content = clean_text(data["content"].to_s)
        title = clean_text(data["title"].to_s.strip)

        {
          title: title,
          content: content
        }
      end

      # Strip excessive DeepSeek backslash-escapes on Markdown syntax:
      # e.g. "\#\# title", "\- bullet", "\_italic\_", "\[link\]".
      def clean_text(text)
        return "" if text.nil?

        text.to_s.gsub(/\\([#\-_*`\[\]()!+>|~])/, '\1')
      end

      private def post_with_retry(path:, payload:, api_key:, base_url:, timeout:)
        raise ArgumentError, "DeepSeek API key is required" if api_key.nil? || api_key.to_s.strip.empty?

        root = (base_url && !base_url.empty?) ? base_url.chomp("/") : DEFAULT_BASE_URL
        uri = URI.parse("#{root}#{path}")

        attempts = 0
        loop do
          attempts += 1
          req = Net::HTTP::Post.new(uri.request_uri)
          req["Content-Type"] = "application/json"
          req["Authorization"] = "Bearer #{api_key}"
          req.body = JSON.generate(payload)

          response = Net::HTTP.start(
            uri.hostname,
            uri.port,
            use_ssl: uri.scheme == "https",
            read_timeout: timeout,
            open_timeout: 10
          ) do |http|
            http.request(req)
          end

          case response.code.to_i
          when 200..299
            return response
          when 429
            if attempts <= MAX_RETRIES
              sleep(1.0 * attempts)
              next
            end
            raise "DeepSeek web tool rate limit exceeded (429)"
          else
            err_msg = response.body.to_s[0, 200]
            raise "DeepSeek web tool #{path} returned HTTP #{response.code}: #{err_msg}"
          end
        end
      end
    end
  end
end
