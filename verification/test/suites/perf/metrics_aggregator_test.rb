require "json"
require_relative "../../test_helper"
require "pathname"
require "tmpdir"
require "time"

require "verification/suites/perf/event_reader"
require "verification/suites/perf/metrics_aggregator"
require "verification/suites/perf/report_builder"
require "verification/suites/perf/benchmark_reporting"

module Verification
  module Perf
    class MetricsAggregatorTest < Minitest::Test
      def test_event_reader_merges_multiple_event_files_in_recorded_order
        with_event_fixture do |paths|
          events = EventReader.read(paths: paths.values_at(:core_matrix, :nexus_01, :nexus_02))

          assert_equal [
            "perf.agent_control.poll",
            "perf.runtime.control_plane_poll",
            "perf.runtime.mailbox_execution",
            "perf.agent_control.mailbox_item_leased",
            "perf.provider_execution.agent_request_exchange_wait",
            "benchmark.workload.item_completed",
            "benchmark.workload.item_completed",
          ], events.first(7).map { |event| event.fetch("event_name") }
          assert_equal events.map { |event| Time.iso8601(event.fetch("recorded_at")) }.sort, events.map { |event| Time.iso8601(event.fetch("recorded_at")) }
        end
      end

      def test_aggregates_percentiles_throughput_queue_pressure_and_db_timeouts
        with_event_fixture do |paths|
          metrics = MetricsAggregator.call(event_paths: paths.values)

          assert_equal 5, metrics.dig("throughput", "completed_workload_items")
          assert_in_delta 1.0, metrics.dig("throughput", "completed_workload_items_per_minute"), 0.001
          assert_equal 2, metrics.dig("throughput", "per_instance", "nexus-01", "completed_workload_items")
          assert_equal 3, metrics.dig("throughput", "per_instance", "nexus-02", "completed_workload_items")

          assert_equal 300.0, metrics.dig("turn_latency", "p50_ms")
          assert_equal 500.0, metrics.dig("turn_latency", "p95_ms")
          assert_equal 500.0, metrics.dig("turn_latency", "p99_ms")
          assert_equal 500.0, metrics.dig("turn_latency", "max_ms")

          assert_equal 450.0, metrics.dig("queue_pressure", "max_queue_delay_ms")
          assert_equal 2, metrics.dig("queue_pressure", "total_sample_count")
          assert_equal 2, metrics.dig("database_checkout_pressure", "timeout_count")
          assert_equal 120.0, metrics.dig("mailbox_exchange_wait", "max_ms")
          assert_equal 80.0, metrics.dig("mailbox_lease_latency", "max_ms")
        end
      end

      def test_report_builder_separates_structural_failures_from_capacity_symptoms
        with_event_fixture do |paths|
          metrics = MetricsAggregator.call(event_paths: paths.values)
          report = ReportBuilder.call(
            profile_name: "smoke",
            agent_count: 1,
            runtime_count: 2,
            metrics: metrics,
            structural_failures: ["nexus-02 failed to boot"],
            gate_result: {
              "kind" => "correctness",
              "eligible" => true,
              "passed" => false,
              "failures" => ["completed_workload_items expected 4, observed 3"],
            },
            artifact_paths: {
              "aggregated_metrics" => "evidence/aggregated-metrics.json",
              "runtime_topology" => "evidence/runtime-topology.json",
            }
          )

          assert_equal "structural_failure", report.dig("outcome", "classification")
          assert_equal ["nexus-02 failed to boot"], report.fetch("structural_failures")
          assert_equal "queue_delay", report.fetch("capacity_symptoms").first.fetch("kind")
          assert_equal "database_checkout_timeouts", report.fetch("strongest_bottleneck_indicators").last.fetch("kind")

          markdown = Verification::BenchmarkReporting.load_summary_markdown(report)
          assert_includes markdown, "Structural Failures"
          assert_includes markdown, "## Gate"
          assert_includes markdown, "completed_workload_items expected 4, observed 3"
          assert_includes markdown, "Capacity Symptoms"
        end
      end

      private

      def with_event_fixture
        Dir.mktmpdir("multi-agent-runtime-metrics-") do |dir|
          root = Pathname(dir)
          paths = {
            core_matrix: root.join("core-matrix-events.ndjson"),
            nexus_01: root.join("nexus-01-events.ndjson"),
            nexus_02: root.join("nexus-02-events.ndjson"),
          }

          write_events(
            paths.fetch(:core_matrix),
            [
              event("2026-04-09T00:00:00Z", "core_matrix", "core-matrix", "perf.agent_control.poll", duration_ms: 40.0, success: true),
              event("2026-04-09T00:00:20Z", "core_matrix", "core-matrix", "perf.agent_control.mailbox_item_leased", success: true, lease_latency_ms: 80.0),
              event("2026-04-09T00:00:30Z", "core_matrix", "core-matrix", "perf.provider_execution.agent_request_exchange_wait", duration_ms: 120.0, success: true),
              event("2026-04-09T00:04:00Z", "core_matrix", "core-matrix", "perf.db.checkout_timeout", success: false),
              event("2026-04-09T00:05:00Z", "core_matrix", "core-matrix", "perf.db.checkout_timeout", success: false),
            ]
          )
          write_events(
            paths.fetch(:nexus_01),
            [
              event("2026-04-09T00:00:10Z", "nexus", "nexus-01", "perf.runtime.control_plane_poll", duration_ms: 20.0, success: true),
              event("2026-04-09T00:00:15Z", "nexus", "nexus-01", "perf.runtime.mailbox_execution", duration_ms: 45.0, success: true),
              event("2026-04-09T00:00:40Z", "verification", "nexus-01", "benchmark.workload.item_completed", duration_ms: 100.0, success: true),
              event("2026-04-09T00:01:40Z", "verification", "nexus-01", "benchmark.workload.item_completed", duration_ms: 200.0, success: true),
              event("2026-04-09T00:02:10Z", "nexus", "nexus-01", "perf.runtime.mailbox_execution_queue_delay", success: true, queue_name: "runtime_control", queue_delay_ms: 150.0),
            ]
          )
          write_events(
            paths.fetch(:nexus_02),
            [
              event("2026-04-09T00:00:50Z", "verification", "nexus-02", "benchmark.workload.item_completed", duration_ms: 300.0, success: true),
              event("2026-04-09T00:02:20Z", "verification", "nexus-02", "benchmark.workload.item_completed", duration_ms: 400.0, success: true),
              event("2026-04-09T00:04:50Z", "verification", "nexus-02", "benchmark.workload.item_completed", duration_ms: 500.0, success: true),
              event("2026-04-09T00:04:55Z", "nexus", "nexus-02", "perf.runtime.mailbox_execution_queue_delay", success: true, queue_name: "runtime_control", queue_delay_ms: 450.0),
            ]
          )

          yield(paths)
        end
      end

      def event(recorded_at, source_app, instance_label, event_name, duration_ms: 0.0, success: true, **extra)
        {
          "recorded_at" => recorded_at,
          "source_app" => source_app,
          "instance_label" => instance_label,
          "event_name" => event_name,
          "duration_ms" => duration_ms,
          "success" => success,
        }.merge(extra.transform_keys(&:to_s))
      end

      def write_events(path, events)
        path.write(events.map { |event| JSON.generate(event) }.join("\n") + "\n")
      end
    end
  end
end
