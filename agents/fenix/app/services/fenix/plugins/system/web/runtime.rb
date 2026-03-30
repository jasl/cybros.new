module Fenix
  module Plugins
    module System
      module Web
        class Runtime
          ValidationError = Class.new(StandardError)

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:)
            @tool_call = tool_call.deep_stringify_keys
          end

          def call
            case @tool_call.fetch("tool_name")
            when "web_fetch"
              Fenix::Web::Fetch.call(url: @tool_call.dig("arguments", "url"))
            when "web_search"
              Fenix::Web::Search.call(
                query: @tool_call.dig("arguments", "query"),
                limit: @tool_call.dig("arguments", "limit"),
                provider: @tool_call.dig("arguments", "provider") || "firecrawl"
              )
            when "firecrawl_search"
              payload = Fenix::Web::FirecrawlClient.search(
                query: @tool_call.dig("arguments", "query"),
                limit: @tool_call.dig("arguments", "limit")
              )
              {
                "provider" => "firecrawl",
                "query" => @tool_call.dig("arguments", "query"),
                "results" => Array(payload.dig("data", "web")),
              }
            when "firecrawl_scrape"
              payload = Fenix::Web::FirecrawlClient.scrape(
                url: @tool_call.dig("arguments", "url"),
                formats: Array(@tool_call.dig("arguments", "formats")).presence || ["markdown"]
              )
              {
                "url" => @tool_call.dig("arguments", "url"),
                "markdown" => payload.dig("data", "markdown").to_s,
                "metadata" => payload.dig("data", "metadata") || {},
              }
            else
              raise ArgumentError, "unsupported web runtime tool #{@tool_call.fetch("tool_name")}"
            end
          rescue Fenix::Web::Fetch::ValidationError,
            Fenix::Web::Fetch::TransportError,
            Fenix::Web::Search::ValidationError,
            Fenix::Web::FirecrawlClient::UnconfiguredError,
            Fenix::Web::FirecrawlClient::RequestError => error
            raise ValidationError, error.message
          end
        end
      end
    end
  end
end
