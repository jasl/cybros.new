module Acceptance
  module Perf
    class ReportBuilder
      def self.call(...)
        new(...).call
      end

      def initialize(profile_name:, runtime_count:, metrics:, structural_failures: [], artifact_paths: {}, gate_result: nil)
        @profile_name = profile_name
        @runtime_count = runtime_count
        @metrics = metrics
        @structural_failures = Array(structural_failures)
        @artifact_paths = artifact_paths
        @gate_result = gate_result
      end

      def call
        {
          "benchmark_mode" => "multi_fenix_core_matrix_load",
          "benchmark_configuration" => {
            "profile_name" => @profile_name,
            "runtime_count" => @runtime_count,
          },
          "outcome" => {
            "classification" => @structural_failures.any? ? "structural_failure" : "descriptive_baseline",
          },
          "structural_failures" => @structural_failures,
          "capacity_symptoms" => capacity_symptoms,
          "strongest_bottleneck_indicators" => strongest_bottleneck_indicators,
          "artifact_paths" => @artifact_paths,
          "metrics" => @metrics,
          "gate" => @gate_result,
        }.compact
      end

      private

      def capacity_symptoms
        symptoms = []

        max_queue_delay_ms = @metrics.dig("queue_pressure", "max_queue_delay_ms")
        if max_queue_delay_ms.to_f.positive?
          symptoms << {
            "kind" => "queue_delay",
            "observed_ms" => max_queue_delay_ms,
          }
        end

        db_timeout_count = @metrics.dig("database_checkout_pressure", "timeout_count").to_i
        if db_timeout_count.positive?
          symptoms << {
            "kind" => "database_checkout_timeouts",
            "count" => db_timeout_count,
          }
        end

        symptoms
      end

      def strongest_bottleneck_indicators
        indicators = []

        queue_delay = @metrics.dig("queue_pressure", "max_queue_delay_ms")
        if queue_delay.to_f.positive?
          indicators << {
            "kind" => "queue_delay",
            "observed_ms" => queue_delay,
          }
        end

        exchange_wait = @metrics.dig("mailbox_exchange_wait", "max_ms")
        if exchange_wait.to_f.positive?
          indicators << {
            "kind" => "mailbox_exchange_wait",
            "observed_ms" => exchange_wait,
          }
        end

        db_timeout_count = @metrics.dig("database_checkout_pressure", "timeout_count").to_i
        if db_timeout_count.positive?
          indicators << {
            "kind" => "database_checkout_timeouts",
            "count" => db_timeout_count,
          }
        end

        indicators
      end
    end
  end
end
