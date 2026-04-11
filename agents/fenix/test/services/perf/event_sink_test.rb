require "test_helper"
require "json"
require "tmpdir"

class Perf::EventSinkTest < ActiveSupport::TestCase
  setup do
    Perf::EventSink.reset!
  end

  teardown do
    Perf::EventSink.reset!
  end

  test "install is inert when perf env vars are absent" do
    result = Perf::EventSink.install!(env: {}, source_app: "fenix")

    ActiveSupport::Notifications.instrument("perf.test", "agent_public_id" => "agent_public_1")

    assert_nil result
    refute Perf::EventSink.enabled?
  end

  test "enabled sink appends one ndjson line and preserves public ids only" do
    Dir.mktmpdir("fenix-perf-") do |tmpdir|
      output_path = File.join(tmpdir, "events.ndjson")

      Perf::EventSink.install!(
        env: {
          "CYBROS_PERF_EVENTS_PATH" => output_path,
          "CYBROS_PERF_INSTANCE_LABEL" => "fenix-01",
        },
        source_app: "fenix"
      )

      ActiveSupport::Notifications.instrument(
        "perf.test",
        "agent_public_id" => "agent_public_1",
        "agent_id" => 123,
        "execution_runtime_connection_id" => "execution-runtime-connection-01",
        "success" => true,
        "metadata" => {
          "phase" => "mailbox",
          "turn_id" => 88,
        }
      )

      lines = File.readlines(output_path, chomp: true)
      assert_equal 1, lines.length

      payload = JSON.parse(lines.first)
      assert_equal "fenix", payload.fetch("source_app")
      assert_equal "fenix-01", payload.fetch("instance_label")
      assert_equal "perf.test", payload.fetch("event_name")
      assert_equal "agent_public_1", payload.fetch("agent_public_id")
      assert_equal "execution-runtime-connection-01", payload.fetch("execution_runtime_connection_id")
      assert_equal true, payload.fetch("success")
      assert_equal({ "phase" => "mailbox" }, payload.fetch("metadata"))
      refute_includes payload.keys, "agent_id"
      assert payload.key?("recorded_at")
      assert_kind_of Numeric, payload.fetch("duration_ms")
    end
  end
end
