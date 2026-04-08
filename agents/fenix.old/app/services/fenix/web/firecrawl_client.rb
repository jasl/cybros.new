require "net/http"

module Fenix
  module Web
    class FirecrawlClient
      UnconfiguredError = Class.new(StandardError)
      RequestError = Class.new(StandardError)
      Response = Struct.new(:status, :headers, :body, keyword_init: true)

      DEFAULT_BASE_URL = "https://api.firecrawl.dev".freeze

      def self.search(...)
        new.search(...)
      end

      def self.scrape(...)
        new.scrape(...)
      end

      def initialize(api_key: ENV["FIRECRAWL_API_KEY"], base_url: ENV.fetch("FIRECRAWL_BASE_URL", DEFAULT_BASE_URL), transport: nil)
        @api_key = api_key.to_s
        @base_url = base_url
        @transport = transport || method(:default_transport)
      end

      def search(query:, limit: nil, scrape_options: nil)
        post_json("/v2/search", {
          "query" => query,
          "limit" => limit,
          "scrape_options" => scrape_options,
        }.compact)
      end

      def scrape(url:, formats: ["markdown"], headers: nil)
        post_json("/v2/scrape", {
          "url" => url,
          "formats" => formats,
          "headers" => headers,
        }.compact)
      end

      private

      def post_json(path, payload)
        raise UnconfiguredError, "FIRECRAWL_API_KEY is required" if @api_key.blank?

        uri = URI.join(@base_url, path)
        request = Net::HTTP::Post.new(uri)
        request["Authorization"] = "Bearer #{@api_key}"
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)

        response = @transport.call(uri, request)
        status = response.status.to_i
        raise RequestError, "Firecrawl request failed with status #{status}" unless status.between?(200, 299)

        JSON.parse(response.body.to_s)
      rescue JSON::ParserError => error
        raise RequestError, "Firecrawl returned invalid JSON: #{error.message}"
      end

      def default_transport(uri, request)
        response = Net::HTTP.start(
          uri.host,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: 5,
          read_timeout: 20,
          write_timeout: 20
        ) do |http|
          http.request(request)
        end

        Response.new(status: response.code.to_i, headers: response.to_hash, body: response.body.to_s)
      end
    end
  end
end
