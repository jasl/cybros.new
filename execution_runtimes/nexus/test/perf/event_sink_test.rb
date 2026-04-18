require "test_helper"
require "json"

class PerfEventSinkTest < Minitest::Test
  def test_build_returns_null_sink_when_perf_env_is_absent
    sink = CybrosNexus::Perf::EventSink.build(env: {}, source_app: "nexus")

    refute sink.enabled?
  end

  def test_enabled_sink_appends_one_ndjson_line_and_preserves_public_ids_only
    output_path = tmp_path("perf/events.ndjson")

    sink = CybrosNexus::Perf::EventSink.build(
      env: {
        "CYBROS_PERF_EVENTS_PATH" => output_path,
        "CYBROS_PERF_INSTANCE_LABEL" => "nexus-01",
      },
      source_app: "nexus"
    )

    sink.record(
      "perf.runtime.mailbox_execution_queue_delay",
      payload: {
        "success" => true,
        "queue_name" => "control_loop",
        "queue_delay_ms" => 4.25,
        "execution_runtime_connection_id" => "execution-runtime-connection-01",
        "conversation_public_id" => "conv_public_1",
        "conversation_id" => 123,
      }
    )

    lines = File.readlines(output_path, chomp: true)
    assert_equal 1, lines.length

    payload = JSON.parse(lines.first)
    assert_equal "nexus", payload.fetch("source_app")
    assert_equal "nexus-01", payload.fetch("instance_label")
    assert_equal "perf.runtime.mailbox_execution_queue_delay", payload.fetch("event_name")
    assert_equal true, payload.fetch("success")
    assert_equal "control_loop", payload.fetch("queue_name")
    assert_equal 4.25, payload.fetch("queue_delay_ms")
    assert_equal "execution-runtime-connection-01", payload.fetch("execution_runtime_connection_id")
    assert_equal "conv_public_1", payload.fetch("conversation_public_id")
    refute_includes payload.keys, "conversation_id"
    assert payload.key?("recorded_at")
    assert_kind_of Numeric, payload.fetch("duration_ms")
    assert sink.enabled?
  end
end
