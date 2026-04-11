require_relative "event_reader"

module Acceptance
  module Perf
    class MetricsAggregator
      def self.call(...)
        new(...).call
      end

      def initialize(event_paths: nil, events: nil)
        @events = events || EventReader.read(paths: event_paths)
      end

      def call
        {
          "event_count" => @events.length,
          "time_window" => time_window,
          "throughput" => throughput_metrics,
          "turn_latency" => percentile_summary(workload_completion_events.map { |event| event.fetch("duration_ms").to_f }),
          "poll_latency" => {
            "fenix_control_plane" => percentile_summary(events_named("perf.runtime.control_plane_poll").map { |event| event.fetch("duration_ms").to_f }),
            "core_matrix_control_plane" => percentile_summary(events_named("perf.agent_control.poll").map { |event| event.fetch("duration_ms").to_f }),
          },
          "mailbox_lease_latency" => percentile_summary(events_named("perf.agent_control.mailbox_item_leased").filter_map { |event| float_or_nil(event["lease_latency_ms"]) }),
          "mailbox_exchange_wait" => percentile_summary(events_named("perf.provider_execution.agent_request_exchange_wait").map { |event| event.fetch("duration_ms").to_f }),
          "queue_pressure" => {
            "max_queue_delay_ms" => queue_delay_values.max,
            "total_sample_count" => queue_delay_values.count,
            "queues" => queue_pressure_by_queue,
          },
          "database_checkout_pressure" => {
            "checkout_wait" => percentile_summary(events_named("perf.db.checkout").map { |event| event.fetch("duration_ms").to_f }),
            "timeout_count" => events_named("perf.db.checkout_timeout").count,
          },
        }
      end

      private

      def workload_completion_events
        events_named("benchmark.workload.item_completed").select { |event| event["success"] == true }
      end

      def throughput_metrics
        runtime_counts = workload_completion_events.group_by { |event| event.fetch("instance_label") }

        {
          "completed_workload_items" => workload_completion_events.count,
          "completed_workload_items_per_minute" => per_minute(workload_completion_events.count),
          "completed_turns" => workload_completion_events.count,
          "completed_turns_per_minute" => per_minute(workload_completion_events.count),
          "completed_mailbox_items" => successful_mailbox_execution_events.count,
          "completed_mailbox_items_per_minute" => per_minute(successful_mailbox_execution_events.count),
          "per_runtime" => runtime_counts.transform_values do |events|
            {
              "completed_workload_items" => events.count,
              "completed_workload_items_per_minute" => per_minute(events.count),
            }
          end,
        }
      end

      def successful_mailbox_execution_events
        events_named("perf.runtime.mailbox_execution").select { |event| event["success"] == true }
      end

      def time_window
        return {} if @events.empty?

        started_at = Time.iso8601(@events.first.fetch("recorded_at"))
        ended_at = Time.iso8601(@events.last.fetch("recorded_at"))

        {
          "started_at" => started_at.iso8601,
          "ended_at" => ended_at.iso8601,
          "duration_seconds" => (ended_at - started_at).round(3),
        }
      end

      def events_named(name)
        @events.select { |event| event.fetch("event_name") == name }
      end

      def queue_delay_values
        @queue_delay_values ||= @events.filter_map { |event| float_or_nil(event["queue_delay_ms"]) }
      end

      def queue_pressure_by_queue
        @events
          .select { |event| event.key?("queue_delay_ms") && event["queue_name"].to_s != "" }
          .group_by { |event| event.fetch("queue_name") }
          .transform_values do |events|
            delays = events.filter_map { |event| float_or_nil(event["queue_delay_ms"]) }
            {
              "max_queue_delay_ms" => delays.max,
              "sample_count" => delays.count,
            }
          end
      end

      def per_minute(count)
        duration_seconds = time_window.fetch("duration_seconds", 0.0).to_f
        return 0.0 if duration_seconds <= 0

        (count.to_f / (duration_seconds / 60.0)).round(3)
      end

      def percentile_summary(values)
        values = values.compact.sort
        return {} if values.empty?

        {
          "count" => values.count,
          "p50_ms" => percentile(values, 50),
          "p95_ms" => percentile(values, 95),
          "p99_ms" => percentile(values, 99),
          "max_ms" => values.max,
        }
      end

      def percentile(values, rank)
        index = [((rank / 100.0) * values.length).ceil - 1, 0].max
        values[[index, values.length - 1].min]
      end

      def float_or_nil(value)
        return if value.nil?

        value.to_f
      end
    end
  end
end
