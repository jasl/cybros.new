require "minitest/autorun"

require_relative "../../../acceptance/lib/perf/profile"

module Acceptance
  module Perf
    class ProfileTest < Minitest::Test
      def test_known_profile_names_and_runtime_counts
        assert_equal %w[smoke target_8_fenix stress], Profile.names

        smoke = Profile.fetch("smoke")
        target = Profile.fetch("target_8_fenix")
        stress = Profile.fetch("stress")

        assert_equal 2, smoke.runtime_count
        assert_equal 8, target.runtime_count
        assert_equal 8, stress.runtime_count
        assert_equal 1, smoke.max_in_flight_per_conversation
        assert_equal 96, stress.expected_completed_workload_items
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
