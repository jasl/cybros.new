require_relative "../../test_helper"

require "verification/suites/perf/profile"

module Verification
  module Perf
    class ProfileTest < Minitest::Test
      def test_known_profile_names_and_runtime_counts
        assert_equal %w[smoke baseline_1_fenix_4_nexus stress], Profile.names

        smoke = Profile.fetch("smoke")
        baseline = Profile.fetch("baseline_1_fenix_4_nexus")
        stress = Profile.fetch("stress")

        assert_equal 2, smoke.runtime_count
        assert_equal 4, baseline.runtime_count
        assert_equal 4, stress.runtime_count
        assert_equal 1, smoke.max_in_flight_per_conversation
        assert_equal 8, stress.expected_completed_workload_items
        assert_equal true, smoke.inline_control_worker?
        assert_equal false, baseline.inline_control_worker?
        assert_equal "pressure", baseline.gate_contract.fetch("kind")
        assert_includes baseline.gate_contract.fetch("required_metric_sample_paths"), "queue_pressure.total_sample_count"
        assert_equal "pressure", stress.gate_contract.fetch("kind")
        assert_includes stress.gate_contract.fetch("required_metric_sample_paths"), "database_checkout_pressure.checkout_wait.count"
      end

      def test_unknown_profile_name_raises_key_error
        error = assert_raises(KeyError) do
          Profile.fetch("not-a-real-profile")
        end

        assert_match(/not-a-real-profile/, error.message)
      end
    end
  end
end
