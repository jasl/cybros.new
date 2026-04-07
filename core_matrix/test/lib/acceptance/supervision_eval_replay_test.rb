require "test_helper"
require Rails.root.join("../acceptance/lib/conversation_artifacts")
require Rails.root.join("../acceptance/lib/supervision_eval_replay")

class AcceptanceSupervisionEvalReplayTest < ActiveSupport::TestCase
  test "replays a supervision evaluation bundle into review markdown" do
    Dir.mktmpdir do |dir|
      review_dir = Pathname(dir).join("review")
      FileUtils.mkdir_p(review_dir)

      bundle_path = review_dir.join("supervision-eval-bundle.json")
      File.write(bundle_path, JSON.pretty_generate({
        "prompt" => "Please tell me what you are doing right now and what changed most recently.",
        "questions" => [
          "Please tell me what you are doing right now and what changed most recently.",
        ],
        "machine_status" => {
          "supervision_session_id" => "sess_public_123",
          "supervision_snapshot_id" => "snap_public_123",
          "conversation_id" => "conv_public_123",
          "overall_state" => "running",
          "board_lane" => "active",
          "request_summary" => "Rebuild supervision around plan-first semantics.",
          "current_focus_summary" => "Rewrite the supervision prompt payload",
          "recent_progress_summary" => "Replace heuristic context facts completed.",
          "primary_turn_todo_plan_view" => {
            "goal_summary" => "Rebuild supervision around the active plan item.",
            "current_item_key" => "rewrite-prompt-payload",
            "current_item" => {
              "title" => "Rewrite the supervision prompt payload",
              "status" => "in_progress",
            },
            "items" => [],
            "counts" => {
              "in_progress" => 1,
              "completed" => 1,
              "total" => 2,
            },
          },
          "turn_feed" => [
            {
              "sequence" => 3,
              "event_kind" => "turn_todo_item_completed",
              "summary" => "Replace heuristic context facts completed.",
              "occurred_at" => "2026-04-07T12:00:00Z",
            },
          ],
          "conversation_context" => {
            "context_snippets" => [
              {
                "role" => "user",
                "slot" => "input",
                "excerpt" => "Sidechat should use the active plan item as the semantic anchor.",
                "keywords" => %w[sidechat active plan item semantic anchor],
              },
            ],
          },
          "runtime_evidence" => {
            "active_command" => {
              "command_run_public_id" => "cmd_public_123",
              "cwd" => "/workspace/core_matrix",
              "command_preview" => "bin/rails test",
              "lifecycle_state" => "running",
            },
          },
          "control" => {
            "supervision_enabled" => true,
            "side_chat_enabled" => true,
            "control_enabled" => true,
            "available_control_verbs" => ["request_status_refresh"],
          },
          "proof_debug" => {},
        },
      }) + "\n")

      result = Acceptance::SupervisionEvalReplay.run!(bundle_path: bundle_path.to_s)

      assert_equal bundle_path.to_s, result.fetch("bundle_path")
      assert_equal "builtin", result.fetch("responder_kind")
      assert_predicate review_dir.join("supervision-sidechat.md"), :exist?
      assert_predicate review_dir.join("supervision-status.md"), :exist?
      assert_predicate review_dir.join("supervision-feed.md"), :exist?
      assert_includes review_dir.join("supervision-sidechat.md").read, "Rewrite the supervision prompt payload"
      assert_includes review_dir.join("supervision-status.md").read, "Runtime evidence"
      assert_includes review_dir.join("supervision-feed.md").read, "Replace heuristic context facts completed."
    end
  end
end
