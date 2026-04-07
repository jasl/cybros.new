require "test_helper"
require Rails.root.join("../acceptance/lib/conversation_artifacts")

class AcceptanceConversationArtifactsTest < ActiveSupport::TestCase
  test "conversation transcript markdown renders ordered messages" do
    markdown = Acceptance::ConversationArtifacts.conversation_transcript_markdown(
      "items" => [
        { "id" => "msg_1", "role" => "user", "content" => "Build 2048" },
        { "id" => "msg_2", "role" => "assistant", "content" => "Working on it" },
      ]
    )

    assert_includes markdown, "# Conversation Transcript"
    assert_includes markdown, "## Message 1"
    assert_includes markdown, "- Message `public_id`: `msg_1`"
    assert_includes markdown, "Build 2048"
    assert_includes markdown, "Working on it"
  end

  test "export roundtrip markdown summarizes transcript and export evidence" do
    markdown = Acceptance::ConversationArtifacts.export_roundtrip_markdown(
      source_conversation_id: "conv_source",
      imported_conversation_id: "conv_imported",
      supervision_trace: {
        "session" => { "conversation_supervision_session" => { "supervision_session_id" => "sup_1" } },
        "polls" => [{}, {}],
        "final_response" => { "machine_status" => { "overall_state" => "idle" } },
      },
      transcript_roundtrip_match: true,
      parsed_debug: {
        "command_runs.json" => [{}, {}],
        "process_runs.json" => [{}],
        "workflow_nodes.json" => [{}, {}, {}],
        "subagent_sessions.json" => [{}],
      }
    )

    assert_includes markdown, "Source conversation:"
    assert_includes markdown, "`conv_source`"
    assert_includes markdown, "`conv_imported`"
    assert_includes markdown, "transcript roundtrip match: `true`"
    assert_includes markdown, "command runs exported: `2`"
    assert_includes markdown, "workflow nodes exported: `3`"
  end

  test "supervision markdown humanizes available control actions" do
    supervision_trace = {
      "polls" => [
        {
          "machine_status" => {
            "supervision_snapshot_id" => "11111111-1111-1111-1111-111111111111",
            "overall_state" => "running",
            "board_lane" => "active",
            "control" => {
              "supervision_enabled" => true,
              "side_chat_enabled" => true,
              "control_enabled" => true,
              "available_control_verbs" => %w[
                request_status_refresh
                request_subagent_close
                send_guidance_to_active_agent
              ],
            },
            "proof_debug" => {},
            "conversation_context" => {},
            "primary_turn_todo_plan_view" => {},
            "active_subagent_turn_todo_plan_views" => [],
            "turn_feed" => [],
            "activity_feed" => [],
          },
          "human_sidechat" => {
            "content" => "I am currently building the React 2048 game.",
          },
          "user_message" => {
            "content" => "What are you doing?",
          },
        },
      ],
      "final_response" => {
        "machine_status" => {
          "supervision_session_id" => "22222222-2222-2222-2222-222222222222",
          "supervision_snapshot_id" => "11111111-1111-1111-1111-111111111111",
          "overall_state" => "running",
          "board_lane" => "active",
          "control" => {
            "supervision_enabled" => true,
            "side_chat_enabled" => true,
            "control_enabled" => true,
            "available_control_verbs" => %w[
              request_status_refresh
              request_subagent_close
              send_guidance_to_active_agent
            ],
          },
          "proof_debug" => {},
          "conversation_context" => {},
          "primary_turn_todo_plan_view" => {},
          "active_subagent_turn_todo_plan_views" => [],
          "turn_feed" => [],
          "activity_feed" => [],
        },
      },
      "session" => {
        "conversation_supervision_session" => {
          "supervision_session_id" => "22222222-2222-2222-2222-222222222222",
        },
      },
    }

    sidechat_markdown = Acceptance::ConversationArtifacts.supervision_sidechat_markdown(
      supervision_trace: supervision_trace,
      prompt: "Please tell me what you are doing right now."
    )
    status_markdown = Acceptance::ConversationArtifacts.supervision_status_markdown(
      supervision_trace: supervision_trace
    )

    refute_includes sidechat_markdown, "request_subagent_close"
    refute_includes sidechat_markdown, "send_guidance_to_active_agent"
    assert_includes sidechat_markdown, "refresh the status snapshot"
    assert_includes sidechat_markdown, "stop the active child task"
    assert_includes sidechat_markdown, "send guidance to the active worker"

    refute_includes status_markdown, "request_subagent_close"
    refute_includes status_markdown, "send_guidance_to_active_agent"
    assert_includes status_markdown, "refresh the status snapshot"
    assert_includes status_markdown, "stop the active child task"
    assert_includes status_markdown, "send guidance to the active worker"
  end

  test "supervision markdown keeps unmapped control actions visible as humanized fallback labels" do
    supervision_trace = {
      "polls" => [
        {
          "machine_status" => {
            "supervision_snapshot_id" => "11111111-1111-1111-1111-111111111111",
            "overall_state" => "running",
            "board_lane" => "active",
            "control" => {
              "supervision_enabled" => true,
              "side_chat_enabled" => true,
              "control_enabled" => true,
              "available_control_verbs" => ["request_custom_pause"],
            },
            "proof_debug" => {},
            "conversation_context" => {},
            "primary_turn_todo_plan_view" => {},
            "active_subagent_turn_todo_plan_views" => [],
            "turn_feed" => [],
            "activity_feed" => [],
          },
          "human_sidechat" => { "content" => "Still working." },
          "user_message" => { "content" => "Status?" },
        },
      ],
      "final_response" => {
        "machine_status" => {
          "supervision_session_id" => "22222222-2222-2222-2222-222222222222",
          "supervision_snapshot_id" => "11111111-1111-1111-1111-111111111111",
          "overall_state" => "running",
          "board_lane" => "active",
          "control" => {
            "supervision_enabled" => true,
            "side_chat_enabled" => true,
            "control_enabled" => true,
            "available_control_verbs" => ["request_custom_pause"],
          },
          "proof_debug" => {},
          "conversation_context" => {},
          "primary_turn_todo_plan_view" => {},
          "active_subagent_turn_todo_plan_views" => [],
          "turn_feed" => [],
          "activity_feed" => [],
        },
      },
      "session" => {
        "conversation_supervision_session" => {
          "supervision_session_id" => "22222222-2222-2222-2222-222222222222",
        },
      },
    }

    markdown = Acceptance::ConversationArtifacts.supervision_status_markdown(supervision_trace: supervision_trace)

    assert_includes markdown, "request custom pause"
  end
end
