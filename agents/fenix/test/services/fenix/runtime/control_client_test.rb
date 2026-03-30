require "test_helper"
require "net/http"

class Fenix::Runtime::ControlClientTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :body, keyword_init: true)

  test "uses ssl when the configured core matrix base url is https" do
    observed = nil
    response = Response.new(code: "200", body: JSON.generate({ "result" => "accepted" }))
    http = Object.new
    http.define_singleton_method(:request) { |_request| response }

    original_start = ::Net::HTTP.method(:start)
    ::Net::HTTP.singleton_class.define_method(:start) do |host, port, use_ssl: false, &block|
      observed = { host:, port:, use_ssl: }
      block.call(http)
    end

    client = Fenix::Runtime::ControlClient.new(
      base_url: "https://core-matrix.example.test",
      machine_credential: "secret"
    )

    client.report!(payload: { "method_id" => "execution_started" })

    assert_equal "core-matrix.example.test", observed.fetch(:host)
    assert_equal 443, observed.fetch(:port)
    assert_equal true, observed.fetch(:use_ssl)
  ensure
    ::Net::HTTP.singleton_class.define_method(:start, original_start)
  end
end
