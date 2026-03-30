require "test_helper"

class Fenix::Web::FetchTest < ActiveSupport::TestCase
  Response = Struct.new(:status, :headers, :body, keyword_init: true)

  test "fetch rejects private and loopback destinations" do
    error = assert_raises(Fenix::Web::Fetch::ValidationError) do
      Fenix::Web::Fetch.call(url: "http://127.0.0.1:3000/admin")
    end

    assert_match(/private or loopback/, error.message)
  end

  test "fetch follows redirects and extracts readable content" do
    transport = lambda do |uri|
      case uri.path
      when "/source"
        Response.new(
          status: 302,
          headers: { "location" => "https://example.com/final" },
          body: ""
        )
      when "/final"
        Response.new(
          status: 200,
          headers: { "content-type" => "text/html; charset=utf-8" },
          body: "<html><body><h1>Hello</h1><p>World</p></body></html>"
        )
      else
        raise "unexpected uri #{uri}"
      end
    end

    result = Fenix::Web::Fetch.call(
      url: "https://example.com/source",
      transport:,
      resolver: ->(_host) { ["93.184.216.34"] }
    )

    assert_equal "https://example.com/final", result.fetch("url")
    assert_equal "Hello World", result.fetch("content")
    assert_equal "text/html", result.fetch("content_type")
    assert_equal 1, result.fetch("redirects")
  end

  test "fetch revalidates redirects before following them" do
    transport = lambda do |_uri|
      Response.new(
        status: 302,
        headers: { "location" => "http://127.0.0.1:4567/private" },
        body: ""
      )
    end

    error = assert_raises(Fenix::Web::Fetch::ValidationError) do
      Fenix::Web::Fetch.call(
        url: "https://example.com/source",
        transport:,
        resolver: ->(_host) { ["93.184.216.34"] }
      )
    end

    assert_match(/private or loopback/, error.message)
  end
end
