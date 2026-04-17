require_relative "../../test_helper"

require "verification/suites/perf/profile"
require "verification/suites/perf/workload_manifest"

module Verification
  module Perf
    class WorkloadManifestTest < Minitest::Test
      def test_baseline_profile_uses_deterministic_single_turn_conversations
        manifest = WorkloadManifest.for_profile(Profile.fetch("baseline_1_fenix_4_nexus"))

        assert manifest.deterministic?
        assert_equal 8, manifest.conversation_count
        assert_equal 1, manifest.max_in_flight_per_conversation
        assert_equal "deterministic_tool", manifest.request_corpus.first.fetch("mode")
        assert_equal({ "expression" => "7 + 5" }, manifest.request_corpus.first.fetch("extra_payload"))
        assert_equal 1, manifest.artifact_payload.fetch("max_in_flight_per_conversation")
      end

      def test_request_corpus_is_stable_for_repeated_fetches
        left = WorkloadManifest.for_profile(Profile.fetch("smoke")).request_corpus
        right = WorkloadManifest.for_profile(Profile.fetch("smoke")).request_corpus

        assert_equal left, right
      end
    end
  end
end
