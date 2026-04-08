module Fenix
  module Web
    class Search
      ValidationError = Class.new(StandardError)

      def self.call(...)
        new(...).call
      end

      def initialize(query:, limit: 5, provider: "firecrawl", firecrawl_client: Fenix::Web::FirecrawlClient)
        @query = query.to_s.strip
        @limit = limit.to_i
        @provider = provider.to_s
        @firecrawl_client = firecrawl_client
      end

      def call
        raise ValidationError, "web_search query must be present" if @query.blank?

        case @provider
        when "firecrawl"
          payload = @firecrawl_client.search(query: @query, limit: normalized_limit)
          {
            "provider" => "firecrawl",
            "query" => @query,
            "results" => Array(payload.dig("data", "web")),
          }
        else
          raise ValidationError, "unsupported web_search provider #{@provider}"
        end
      end

      private

      def normalized_limit
        return 5 if @limit <= 0

        @limit
      end
    end
  end
end
