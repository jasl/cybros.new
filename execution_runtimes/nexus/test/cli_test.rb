require "test_helper"

class CliTest < Minitest::Test
  DummyConfig = Struct.new(:core_matrix_base_url)
  DummySessionClient = Struct.new(:connection_credential)

  def test_build_action_cable_client_uses_idle_timeout_to_bound_ping_only_connections
    cli = CybrosNexus::CLI.new
    config = DummyConfig.new("http://core-matrix.example.test")
    session_client = DummySessionClient.new("runtime-secret")
    captured = nil

    original_timeout = ENV["REALTIME_TIMEOUT_SECONDS"]
    ENV["REALTIME_TIMEOUT_SECONDS"] = "7"

    action_cable_class = CybrosNexus::Transport::ActionCableClient.singleton_class
    original_new = CybrosNexus::Transport::ActionCableClient.method(:new)

    action_cable_class.define_method(:new) do |**kwargs|
      captured = kwargs
      Object.new
    end

    begin
      cli.send(:build_action_cable_client, config: config, session_client: session_client)
    ensure
      action_cable_class.define_method(:new, original_new)
    end

    assert_equal "http://core-matrix.example.test", captured.fetch(:base_url)
    assert_equal "runtime-secret", captured.fetch(:credential)
    assert_equal 7, captured.fetch(:timeout_seconds)
    assert_equal 7, captured.fetch(:mailbox_item_timeout_seconds)
  ensure
    ENV["REALTIME_TIMEOUT_SECONDS"] = original_timeout
  end
end
