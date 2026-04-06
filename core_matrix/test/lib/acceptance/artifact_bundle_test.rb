require "test_helper"
require Rails.root.join("../acceptance/lib/artifact_bundle")

class AcceptanceArtifactBundleTest < ActiveSupport::TestCase
  test "review index exposes playable and evidence entry points" do
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
      assert_includes body, "[Subagent Runtime Snapshots](../evidence/subagent-runtime-snapshots.json)"
      assert_includes body, "[Live Progress Feed](../logs/live-progress-events.jsonl)"
      assert_includes body, "[Playable Outputs](../playable/)"
    end
  end

  test "root readme describes canonical artifact layout only" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("README.md")

      Acceptance::ArtifactBundle.write_root_readme!(
        path: path,
        artifact_stamp: "stamp_123",
        summary: {
          "benchmark_outcome" => "pass_clean",
          "workload_outcome" => "complete",
          "system_behavior_outcome" => "healthy",
        }
      )

      body = path.read
      assert_includes body, "[Review index](review/index.md)"
      assert_includes body, "[Benchmark summary](evidence/run-summary.json)"
      refute_includes body, "compatibility"
      refute_includes body, "legacy root-level duplicates"
    end
  end

  test "manifest exposes canonical review and evidence entrypoints" do
    Dir.mktmpdir do |dir|
      path = Pathname(dir).join("artifact-manifest.json")

      Acceptance::ArtifactBundle.write_manifest!(
        path: path,
        artifact_stamp: "stamp_123",
        summary: {
          "benchmark_outcome" => "pass_clean",
          "workload_outcome" => "complete",
          "system_behavior_outcome" => "healthy",
        }
      )

      payload = JSON.parse(path.read)
      assert_equal "stamp_123", payload.fetch("artifact_stamp")
      assert_equal "review/index.md", payload.dig("entry_points", "review_index")
      assert_equal "evidence/run-summary.json", payload.dig("entry_points", "benchmark_summary")
      assert_equal "evidence/subagent-runtime-snapshots.json", payload.dig("entry_points", "subagent_runtime_snapshots")
      assert_equal "logs/live-progress-events.jsonl", payload.dig("entry_points", "live_progress_feed")
    end
  end
end
