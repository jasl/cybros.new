require "minitest/autorun"

require_relative "../../../acceptance/lib/perf/profile"
require_relative "../../../acceptance/lib/perf/workload_manifest"

module Acceptance
  module Perf
    class WorkloadManifestTest < Minitest::Test
      def test_target_profile_uses_deterministic_single_turn_conversations
        manifest = WorkloadManifest.for_profile(Profile.fetch("target_8_fenix"))

        assert manifest.deterministic?
        assert_equal 16, manifest.conversation_count
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
