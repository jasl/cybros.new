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
    ::Net::HTTP.singleton_class.define_method(:start) do |host, port, use_ssl: false, open_timeout: nil, read_timeout: nil, write_timeout: nil, &block|
      observed = { host:, port:, use_ssl:, open_timeout:, read_timeout:, write_timeout: }
      block.call(http)
    end

    client = Fenix::Runtime::ControlClient.new(
      base_url: "https://core-matrix.example.test",
      machine_credential: "secret",
      open_timeout: 3,
      read_timeout: 11,
      write_timeout: 17
    )

    client.report!(payload: { "method_id" => "execution_started" })

    assert_equal "core-matrix.example.test", observed.fetch(:host)
    assert_equal 443, observed.fetch(:port)
    assert_equal true, observed.fetch(:use_ssl)
    assert_equal 3, observed.fetch(:open_timeout)
    assert_equal 11, observed.fetch(:read_timeout)
    assert_equal 17, observed.fetch(:write_timeout)
  ensure
    ::Net::HTTP.singleton_class.define_method(:start, original_start)
  end
end
