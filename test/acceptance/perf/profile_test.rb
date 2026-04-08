require "minitest/autorun"

require_relative "../../../acceptance/lib/perf/profile"

module Acceptance
  module Perf
    class ProfileTest < Minitest::Test
      def test_known_profile_names_and_runtime_counts
        assert_equal %w[smoke target_8_fenix stress], Profile.names

        assert_equal 2, Profile.fetch("smoke").runtime_count
        assert_equal 8, Profile.fetch("target_8_fenix").runtime_count
        assert_equal 8, Profile.fetch("stress").runtime_count
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
