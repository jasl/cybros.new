require "test_helper"
require Rails.root.join("../acceptance/lib/capstone_review_artifacts")
require "tmpdir"

class Acceptance::CapstoneReviewArtifactsTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "install! writes a workflow mermaid review with specialist labels" do
    fixture = build_workflow_proof_fixture!(with_subagent_spawn: true)
    fixture.fetch(:workflow_run).update!(
      wait_state: "waiting",
      wait_reason_kind: "human_interaction",
      waiting_since_at: Time.current
    )
    later_turn = Turns::StartUserTurn.call(
      conversation: fixture.fetch(:conversation),
      content: "Later proof export input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    later_workflow_run = create_workflow_run!(
      turn: later_turn,
      lifecycle_state: "completed"
    )
    debug_payload = ConversationDebugExports::BuildPayload.call(conversation: fixture.fetch(:conversation))

    Dir.mktmpdir do |dir|
      artifact_dir = Pathname.new(dir)
      conversation_export_path = artifact_dir.join("exports", "conversation-export.zip")
      conversation_debug_export_path = artifact_dir.join("exports", "conversation-debug-export.zip")
      write_zip_fixture(
        conversation_export_path,
        "transcript.md" => "# Transcript\n",
        "conversation.html" => "<html><body>Transcript</body></html>"
      )
      write_zip_fixture(
        conversation_debug_export_path,
        "conversation.json" => "{}"
      )

      workflow_run_singleton = WorkflowRun.singleton_class
      proof_export_singleton = Workflows::ProofExportQuery.singleton_class
      original_find_by = workflow_run_singleton.instance_method(:find_by)
      original_call = proof_export_singleton.instance_method(:call)

      begin
        workflow_run_singleton.send(:define_method, :find_by) do |*|
          raise "workflow review should use debug export payload, not live db lookups"
        end
        proof_export_singleton.send(:define_method, :call) do |*|
          raise "workflow review should not re-run proof export queries"
        end

        Acceptance::CapstoneReviewArtifacts.install!(
          artifact_dir: artifact_dir,
          conversation_export_path: conversation_export_path,
          conversation_debug_export_path: conversation_debug_export_path,
          turn_feed: { "items" => [] },
          turn_runtime_events: { "summary" => { "event_count" => 0, "lane_count" => 0 }, "segments" => [] },
          debug_payload: debug_payload,
          workflow_run_id: fixture.fetch(:workflow_run).public_id
        )
      ensure
        workflow_run_singleton.send(:define_method, :find_by, original_find_by)
        proof_export_singleton.send(:define_method, :call, original_call)
      end

      review = artifact_dir.join("review", "workflow-mermaid.md").read
      index = artifact_dir.join("review", "index.md").read

      assert_includes review, "# Workflow Mermaid"
      assert_includes review, "```mermaid"
      assert_includes review, "flowchart LR"
      assert_includes review, "Selected workflow run: `#{fixture.fetch(:workflow_run).public_id}`"
      refute_includes review, later_workflow_run.public_id
      assert_includes review, " --> "
      assert_includes review, "yield batch: batch-1"
      assert_includes review, "barrier: wait_all"
      assert_includes review, "specialist: researcher"
      assert_includes review, "wait: human_interaction"
      assert_includes index, "[Workflow Mermaid](workflow-mermaid.md)"
    end
  end

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

  private

  def write_zip_fixture(path, entries)
    FileUtils.mkdir_p(path.dirname)
    Zip::OutputStream.open(path.to_s) do |zip|
      entries.each do |entry_name, contents|
        zip.put_next_entry(entry_name)
        zip.write(contents)
      end
    end
  end
end
