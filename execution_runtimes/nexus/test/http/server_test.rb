require "test_helper"
require "json"
require "net/http"
require "socket"

class HttpServerTest < Minitest::Test
  def test_serves_runtime_manifest_and_health_endpoints
    config = CybrosNexus::Config.load(
      env: {
        "NEXUS_HTTP_BIND" => "127.0.0.1",
        "NEXUS_HTTP_PORT" => available_port.to_s,
        "NEXUS_PUBLIC_BASE_URL" => nil,
      }.compact,
      home_dir: tmp_root
    )
    manifest = CybrosNexus::Session::RuntimeManifest.new(config: config)
    server = CybrosNexus::HTTP::Server.new(config: config, manifest: manifest)
    thread = Thread.new { server.start }

    wait_until_ready!(server.base_url)

    manifest_response = Net::HTTP.get_response(URI("#{server.base_url}/runtime/manifest"))
    live_response = Net::HTTP.get_response(URI("#{server.base_url}/health/live"))

    assert_equal "200", manifest_response.code
    assert_equal "200", live_response.code

    body = JSON.parse(manifest_response.body)
    assert_equal "/runtime/manifest", body.dig("endpoint_metadata", "runtime_manifest_path")
    assert_equal "Nexus", body.fetch("display_name")
    assert_equal "execution_runtime", body.dig("execution_runtime_plane", "control_plane")
  ensure
    server&.stop
    thread&.join(1)
  end

  private

  def available_port
    TCPServer.open("127.0.0.1", 0) do |server|
      return server.addr[1]
    end
  end

  def wait_until_ready!(base_url)
    deadline_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5

    loop do
      response = Net::HTTP.get_response(URI("#{base_url}/health/live"))
      return if response.code == "200"
    rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH
      raise "timed out waiting for HTTP server" if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline_at

      sleep(0.05)
    end
  end
end
