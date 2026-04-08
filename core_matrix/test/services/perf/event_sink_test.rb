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
    result = Perf::EventSink.install!(env: {}, source_app: "core_matrix")

    ActiveSupport::Notifications.instrument("perf.test", "conversation_public_id" => "conv_public")

    assert_nil result
    refute Perf::EventSink.enabled?
  end

  test "enabled sink appends one ndjson line and preserves public ids only" do
    Dir.mktmpdir("core-matrix-perf-") do |tmpdir|
      output_path = File.join(tmpdir, "events.ndjson")

      Perf::EventSink.install!(
        env: {
          "CYBROS_PERF_EVENTS_PATH" => output_path,
          "CYBROS_PERF_INSTANCE_LABEL" => "core-matrix-01",
        },
        source_app: "core_matrix"
      )

      ActiveSupport::Notifications.instrument(
        "perf.test",
        "conversation_public_id" => "conv_public",
        "conversation_id" => 42,
        "executor_session_id" => "executor-session-01",
        "success" => true,
        "metadata" => {
          "phase" => "poll",
          "turn_id" => 88,
        }
      )

      lines = File.readlines(output_path, chomp: true)
      assert_equal 1, lines.length

      payload = JSON.parse(lines.first)
      assert_equal "core_matrix", payload.fetch("source_app")
      assert_equal "core-matrix-01", payload.fetch("instance_label")
      assert_equal "perf.test", payload.fetch("event_name")
      assert_equal "conv_public", payload.fetch("conversation_public_id")
      assert_equal "executor-session-01", payload.fetch("executor_session_id")
      assert_equal true, payload.fetch("success")
      assert_equal({ "phase" => "poll" }, payload.fetch("metadata"))
      refute_includes payload.keys, "conversation_id"
      assert payload.key?("recorded_at")
      assert_kind_of Numeric, payload.fetch("duration_ms")
    end
  end

  test "install prefers core matrix specific perf env over shared cybros env" do
    Dir.mktmpdir("core-matrix-perf-") do |tmpdir|
      core_matrix_output_path = File.join(tmpdir, "core-matrix-events.ndjson")
      runtime_output_path = File.join(tmpdir, "fenix-events.ndjson")

      Perf::EventSink.install!(
        env: {
          "CORE_MATRIX_PERF_EVENTS_PATH" => core_matrix_output_path,
          "CORE_MATRIX_PERF_INSTANCE_LABEL" => "core-matrix-01",
          "CYBROS_PERF_EVENTS_PATH" => runtime_output_path,
          "CYBROS_PERF_INSTANCE_LABEL" => "fenix-01",
        },
        source_app: "core_matrix"
      )

      ActiveSupport::Notifications.instrument("perf.test", "conversation_public_id" => "conv_public")

      assert File.exist?(core_matrix_output_path), "expected core matrix output path to receive the event"
      refute File.exist?(runtime_output_path), "expected shared runtime output path to stay untouched"

      payload = JSON.parse(File.readlines(core_matrix_output_path, chomp: true).first)
      assert_equal "core-matrix-01", payload.fetch("instance_label")
      assert_equal "core_matrix", payload.fetch("source_app")
    end
  end
end
