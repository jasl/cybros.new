require "minitest/autorun"

require_relative "../../../acceptance/lib/perf/profile"
require_relative "../../../acceptance/lib/perf/gate_evaluator"

module Acceptance
  module Perf
    class GateEvaluatorTest < Minitest::Test
      def test_smoke_gate_passes_for_expected_completed_items_without_structural_failures
        result = GateEvaluator.call(
          profile: Profile.fetch("smoke"),
          metrics: {},
          structural_failures: [],
          completed_workload_items: 4
        )

        assert_equal "correctness", result.fetch("kind")
        assert_equal true, result.fetch("eligible")
        assert_equal true, result.fetch("passed")
        assert_empty result.fetch("failures")
      end

      def test_stress_gate_requires_pressure_samples_and_zero_db_timeouts
        result = GateEvaluator.call(
          profile: Profile.fetch("stress"),
          metrics: {
            "mailbox_lease_latency" => {},
            "mailbox_exchange_wait" => { "count" => 12 },
            "queue_pressure" => { "total_sample_count" => 9 },
            "database_checkout_pressure" => {
              "checkout_wait" => { "count" => 0 },
              "timeout_count" => 1,
            },
          },
          structural_failures: [],
          completed_workload_items: 96
        )

        assert_equal false, result.fetch("passed")
        assert_includes result.fetch("failures"), "mailbox_lease_latency.count expected positive sample count, observed nil"
        assert_includes result.fetch("failures"), "database_checkout_pressure.checkout_wait.count expected positive sample count, observed 0"
        assert_includes result.fetch("failures"), "database checkout timeouts expected at most 0, observed 1"
      end
    end
  end
end
