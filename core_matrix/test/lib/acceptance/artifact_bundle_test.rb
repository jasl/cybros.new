require "test_helper"
require Rails.root.join("../acceptance/lib/artifact_bundle")

class AcceptanceArtifactBundleTest < ActiveSupport::TestCase
  test "default layout and review index expose playable and evidence entry points" do
    assert_includes Acceptance::ArtifactBundle::DEFAULT_LAYOUT.fetch("playable"), "host-playwright-install.json"
    assert_includes Acceptance::ArtifactBundle::DEFAULT_LAYOUT.fetch("playable"), "host-playwright-test.json"
    assert_includes Acceptance::ArtifactBundle::DEFAULT_LAYOUT.fetch("logs"), "live-progress-events.jsonl"

    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("review-index.md")

      Acceptance::ArtifactBundle.write_review_index!(
        path: path,
        summary: {
          "conversation_id" => "conv_123",
          "turn_id" => "turn_123",
          "workflow_run_id" => "run_123",
          "benchmark_outcome" => "pass_recovered",
          "workload_outcome" => "complete",
          "system_behavior_outcome" => "healthy_with_recovery",
        }
      )

      body = path.read
      assert_includes body, "[Turn Runtime Transcript](turn-runtime-transcript.md)"
      assert_includes body, "[Turn Runtime Evidence](../evidence/turn-runtime-evidence.json)"
      assert_includes body, "[Live Progress Feed](../logs/live-progress-events.jsonl)"
      assert_includes body, "[Playable Outputs](../playable/)"
    end
  end
end
