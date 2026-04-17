require_relative "../../test_helper"
require "tmpdir"
require "fileutils"
require "pathname"
require "zip"
require "active_support/core_ext/object/blank"

require "verification/suites/proof/capstone_review_artifacts"

module Verification
  class CapstoneReviewArtifactsTest < Minitest::Test
    def test_install_writes_review_files_and_copies_transcript_artifacts
      Dir.mktmpdir("capstone-review-artifacts") do |dir|
        artifact_dir = Pathname.new(dir)
        export_zip = artifact_dir.join("exports", "conversation-export.zip")
        debug_zip = artifact_dir.join("exports", "conversation-debug-export.zip")
        FileUtils.mkdir_p(export_zip.dirname)

        write_zip(
          export_zip,
          "transcript.md" => "# Transcript\n\nHello from transcript.\n",
          "conversation.html" => "<html><body>hello html</body></html>",
          "conversation.json" => "{\"conversation\":{\"public_id\":\"conv_123\"}}"
        )
        write_zip(debug_zip, "conversation.json" => "{\"conversation\":{\"public_id\":\"conv_123\"}}")

        with_workflow_mermaid_review("# Workflow Mermaid\n\nSelected workflow run: `run_123`\n") do
          Verification::CapstoneReviewArtifacts.install!(
            artifact_dir: artifact_dir,
            conversation_export_path: export_zip,
            conversation_debug_export_path: debug_zip,
            turn_feed: {
              "items" => [
                {
                  "event_kind" => "turn_started",
                  "summary" => "Turn started",
                  "occurred_at" => "2026-04-14T00:00:00Z",
                  "details_payload" => { "board_lane" => "running" }
                }
              ]
            },
            turn_runtime_events: {
              "summary" => { "event_count" => 2, "lane_count" => 1 },
              "segments" => [
                {
                  "key" => "plan",
                  "title" => "Plan",
                  "events" => [
                    {
                      "timestamp" => "2026-04-14T00:00:01Z",
                      "kind" => "workflow_step_started",
                      "summary" => "Started the plan step"
                    }
                  ]
                }
              ],
              "items" => []
            },
            debug_payload: {
              "diagnostics" => {
                "conversation" => {
                  "lifecycle_state" => "active",
                  "turn_count" => 1,
                  "provider_round_count" => 2,
                  "tool_call_count" => 1,
                  "command_run_count" => 1,
                  "process_run_count" => 0,
                  "subagent_connection_count" => 0,
                  "metadata" => {
                    "tool_breakdown" => {
                      "exec_command" => { "count" => 1, "failures" => 0 }
                    }
                  }
                },
                "turns" => [
                  {
                    "turn_id" => "turn_123",
                    "lifecycle_state" => "completed",
                    "provider_round_count" => 2,
                    "tool_call_count" => 1
                  }
                ]
              },
              "subagent_connections" => [],
              "workflow_runs" => [
                {
                  "workflow_run_id" => "run_123",
                  "created_at" => "2026-04-14T00:00:00Z"
                }
              ]
            },
            workflow_run_id: "run_123"
          )
        end

        review_dir = artifact_dir.join("review")
        assert review_dir.join("workflow-mermaid.md").exist?
        assert_includes review_dir.join("workflow-mermaid.md").read, "Selected workflow run: `run_123`"
        assert_includes review_dir.join("index.md").read, "Workflow Mermaid"
      end
    end

    def test_install_writes_supervision_sidechat_transcript_when_messages_exist
      Dir.mktmpdir("capstone-review-artifacts") do |dir|
        artifact_dir = Pathname.new(dir)
        export_zip = artifact_dir.join("exports", "conversation-export.zip")
        debug_zip = artifact_dir.join("exports", "conversation-debug-export.zip")
        FileUtils.mkdir_p(export_zip.dirname)

        write_zip(
          export_zip,
          "transcript.md" => "# Transcript\n\nHello from transcript.\n",
          "conversation.html" => "<html><body>hello html</body></html>"
        )
        write_zip(debug_zip, "conversation.json" => "{\"conversation\":{\"public_id\":\"conv_123\"}}")

        with_workflow_mermaid_review("# Workflow Mermaid\n") do
          Verification::CapstoneReviewArtifacts.install!(
            artifact_dir: artifact_dir,
            conversation_export_path: export_zip,
            conversation_debug_export_path: debug_zip,
            turn_feed: { "items" => [] },
            turn_runtime_events: { "summary" => { "event_count" => 0, "lane_count" => 0 }, "segments" => [], "items" => [] },
            debug_payload: {
              "diagnostics" => {
                "conversation" => {
                  "lifecycle_state" => "active",
                  "turn_count" => 1,
                  "provider_round_count" => 0,
                  "tool_call_count" => 0,
                  "command_run_count" => 0,
                  "process_run_count" => 0,
                  "subagent_connection_count" => 0,
                  "metadata" => {}
                },
                "turns" => []
              },
              "subagent_connections" => [],
              "conversation_supervision_sessions" => [
                {
                  "supervision_session_id" => "session_123",
                  "target_conversation_id" => "conv_123",
                  "initiator_type" => "User",
                  "initiator_id" => "user_123",
                  "lifecycle_state" => "open",
                  "responder_strategy" => "builtin",
                  "created_at" => "2026-04-14T00:00:00Z"
                }
              ],
              "conversation_supervision_messages" => [
                {
                  "supervision_message_id" => "msg_user_123",
                  "supervision_session_id" => "session_123",
                  "supervision_snapshot_id" => "snapshot_123",
                  "target_conversation_id" => "conv_123",
                  "role" => "user",
                  "content" => "What changed most recently?",
                  "created_at" => "2026-04-14T00:00:01Z"
                },
                {
                  "supervision_message_id" => "msg_supervisor_123",
                  "supervision_session_id" => "session_123",
                  "supervision_snapshot_id" => "snapshot_123",
                  "target_conversation_id" => "conv_123",
                  "role" => "supervisor_agent",
                  "content" => "Most recently the conversation completed the requested work.",
                  "created_at" => "2026-04-14T00:00:02Z"
                }
              ]
            },
            workflow_run_id: "run_123"
          )
        end

        review_dir = artifact_dir.join("review")
        assert review_dir.join("supervision-sidechat.md").exist?
        refute_includes review_dir.join("supervision-feed.md").read, "No supervision sidechat was captured"
        assert_includes review_dir.join("supervision-sidechat.md").read, "What changed most recently?"
        assert_includes review_dir.join("supervision-sidechat.md").read, "Most recently the conversation completed the requested work."
        assert_includes review_dir.join("index.md").read, "Supervision Sidechat"
      end
    end

    private

    def write_zip(path, entries)
      Zip::File.open(path.to_s, create: true) do |zip|
        entries.each do |name, body|
          zip.get_output_stream(name) { |stream| stream.write(body) }
        end
      end
    end

    def with_workflow_mermaid_review(review)
      singleton = Verification::CapstoneReviewArtifacts.singleton_class
      original = singleton.instance_method(:build_workflow_mermaid_review)

      singleton.send(:undef_method, :build_workflow_mermaid_review)
      singleton.send(:define_method, :build_workflow_mermaid_review) do |*|
        review
      end

      yield
    ensure
      singleton.send(:undef_method, :build_workflow_mermaid_review)
      singleton.send(:define_method, :build_workflow_mermaid_review, original)
    end
  end
end
