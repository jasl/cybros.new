require "test_helper"
require Rails.root.join("../acceptance/lib/capstone_review_artifacts")
require "tmpdir"

class Acceptance::CapstoneReviewArtifactsTest < ActiveSupport::TestCase
  test "install_live_supervision_sidechat! writes readable review artifacts" do
    Dir.mktmpdir do |dir|
      artifact_dir = Pathname.new(dir)
      debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
      FileUtils.mkdir_p(debug_export_path.dirname)
      File.binwrite(debug_export_path, "debug-export-placeholder")

      debug_payload = {
        "diagnostics" => {
          "conversation" => {
            "lifecycle_state" => "active",
            "turn_count" => 1,
            "provider_round_count" => 0,
            "tool_call_count" => 0,
            "command_run_count" => 0,
            "process_run_count" => 0,
            "subagent_connection_count" => 0,
            "metadata" => {},
          },
          "turns" => [
            {
              "turn_id" => "turn_public_id",
              "lifecycle_state" => "active",
              "provider_round_count" => 0,
              "tool_call_count" => 0,
            },
          ],
        },
        "conversation_supervision_sessions" => [
          {
            "supervision_session_id" => "session_public_id",
            "responder_strategy" => "builtin",
            "lifecycle_state" => "open",
            "created_at" => "2026-04-14T00:00:00Z",
          },
        ],
        "conversation_supervision_messages" => [
          {
            "supervision_session_id" => "session_public_id",
            "role" => "user",
            "content" => "What are you doing right now?",
            "created_at" => "2026-04-14T00:00:01Z",
          },
          {
            "supervision_session_id" => "session_public_id",
            "role" => "supervisor_agent",
            "content" => "Right now I am checking progress.",
            "created_at" => "2026-04-14T00:00:02Z",
          },
        ],
      }

      Acceptance::CapstoneReviewArtifacts.install_live_supervision_sidechat!(
        artifact_dir: artifact_dir,
        conversation_debug_export_path: debug_export_path,
        debug_payload: debug_payload,
        conversation_id: "conversation_public_id",
        turn_id: "turn_public_id",
        workflow_run_id: "workflow_run_public_id",
        observed_conversation_state: {
          "conversation_state" => "active",
          "turn_lifecycle_state" => "active",
          "workflow_wait_state" => "waiting",
          "machine_status" => "blocked",
        },
        status_probe_content: "Right now I am checking progress.",
        blocker_probe_content: "Waiting for operator confirmation."
      )

      review_dir = artifact_dir.join("review")
      assert review_dir.join("index.md").exist?
      assert review_dir.join("summary.md").exist?
      assert review_dir.join("diagnostics-summary.md").exist?
      assert review_dir.join("supervision-sidechat.md").exist?

      transcript = review_dir.join("supervision-sidechat.md").read
      assert_includes transcript, "Session `session_public_id`"
      assert_includes transcript, "What are you doing right now?"
      assert_includes transcript, "Right now I am checking progress."

      summary = review_dir.join("summary.md").read
      assert_includes summary, "conversation id: `conversation_public_id`"
      assert_includes summary, "workflow wait state: `waiting`"
      assert_includes summary, "Waiting for operator confirmation."
    end
  end
end
