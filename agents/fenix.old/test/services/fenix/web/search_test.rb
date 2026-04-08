require "test_helper"

class Fenix::Web::SearchTest < ActiveSupport::TestCase
  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  test "firecrawl client posts search requests with bearer authorization" do
    captured = {}
    transport = lambda do |uri, request|
      captured[:uri] = uri
      captured[:headers] = request.to_hash
      captured[:body] = JSON.parse(request.body)

      Response.new(
        status: 200,
        headers: { "content-type" => "application/json" },
        body: JSON.generate(
          "success" => true,
          "data" => { "web" => [{ "url" => "https://example.com", "title" => "Example" }] }
        )
      )
    end

    payload = Fenix::Web::FirecrawlClient.new(
      api_key: "fc-test",
      transport:,
      base_url: "https://api.firecrawl.dev"
    ).search(query: "agents", limit: 3)

    assert_equal "https://api.firecrawl.dev/v2/search", captured.fetch(:uri).to_s
    assert_equal ["Bearer fc-test"], captured.fetch(:headers).fetch("authorization")
    assert_equal "agents", captured.fetch(:body).fetch("query")
    assert_equal 3, captured.fetch(:body).fetch("limit")
    assert_equal "Example", payload.dig("data", "web", 0, "title")
  end

  test "firecrawl client posts scrape requests with bearer authorization" do
    captured = {}
    transport = lambda do |uri, request|
      captured[:uri] = uri
      captured[:headers] = request.to_hash
      captured[:body] = JSON.parse(request.body)

      Response.new(
        status: 200,
        headers: { "content-type" => "application/json" },
        body: JSON.generate(
          "success" => true,
          "data" => { "markdown" => "# Example", "metadata" => { "title" => "Example" } }
        )
      )
    end

    payload = Fenix::Web::FirecrawlClient.new(
      api_key: "fc-test",
      transport:,
      base_url: "https://api.firecrawl.dev"
    ).scrape(url: "https://example.com", formats: ["markdown"])

    assert_equal "https://api.firecrawl.dev/v2/scrape", captured.fetch(:uri).to_s
    assert_equal ["Bearer fc-test"], captured.fetch(:headers).fetch("authorization")
    assert_equal "https://example.com", captured.fetch(:body).fetch("url")
    assert_equal ["markdown"], captured.fetch(:body).fetch("formats")
    assert_equal "# Example", payload.dig("data", "markdown")
  end

  test "generic web_search delegates to the firecrawl provider" do
    fake_client = Class.new do
      def self.search(query:, limit:, scrape_options: nil)
        {
          "success" => true,
          "data" => {
            "web" => [
              {
                "url" => "https://example.com",
                "title" => "Example",
                "description" => "Search result",
                "markdown" => "# Example",
              },
            ],
          },
        }
      end
    end

    result = Fenix::Web::Search.call(
      query: "agents",
      limit: 2,
      provider: "firecrawl",
      firecrawl_client: fake_client
    )

    assert_equal "firecrawl", result.fetch("provider")
    assert_equal "agents", result.fetch("query")
    assert_equal "Example", result.fetch("results").first.fetch("title")
  end
end
