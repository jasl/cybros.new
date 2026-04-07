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

  test "supervision status markdown shows no active work for an idle final poll" do
    idle_poll = {
      "machine_status" => {
        "supervision_snapshot_id" => "33333333-3333-3333-3333-333333333333",
        "overall_state" => "idle",
        "board_lane" => "idle",
        "last_terminal_state" => "completed",
        "last_terminal_at" => "2026-04-07T09:47:28.000000Z",
        "current_focus_summary" => nil,
        "recent_progress_summary" => "Started the preview server in /workspace/game-2048",
        "runtime_focus_hint" => nil,
        "primary_turn_todo_plan_view" => {
          "goal_summary" => "Fix the existing app in /workspace/game-2048.",
          "current_item_key" => "fixing-the-existing-app-in-workspace-game-2048",
          "current_item" => {
            "title" => "Fixing the existing app in /workspace/game-2048",
            "status" => "completed",
          },
          "items" => [],
          "counts" => {
            "in_progress" => 0,
            "completed" => 3,
            "total" => 3,
          },
        },
        "active_subagent_turn_todo_plan_views" => [],
        "turn_feed" => [
          {
            "sequence" => 6,
            "event_kind" => "turn_todo_item_completed",
            "summary" => "Completed fixing the existing app in /workspace/game-2048.",
            "occurred_at" => "2026-04-07T09:47:28.000000Z",
          },
        ],
        "activity_feed" => [],
        "control" => {
          "supervision_enabled" => true,
          "side_chat_enabled" => true,
          "control_enabled" => true,
          "available_control_verbs" => ["request_status_refresh"],
        },
        "proof_debug" => {},
        "conversation_context" => {},
      },
      "human_sidechat" => {
        "content" => "Right now I’m idle. Most recently, I started the preview server in /workspace/game-2048.",
      },
      "user_message" => {
        "content" => "What are you doing?",
      },
    }
    supervision_trace = {
      "polls" => [
        {
          "machine_status" => {
            "supervision_snapshot_id" => "11111111-1111-1111-1111-111111111111",
            "overall_state" => "queued",
            "board_lane" => "queued",
            "primary_turn_todo_plan_view" => {},
            "active_subagent_turn_todo_plan_views" => [],
            "turn_feed" => [],
            "activity_feed" => [],
            "control" => {
              "supervision_enabled" => true,
              "side_chat_enabled" => true,
              "control_enabled" => true,
              "available_control_verbs" => ["request_status_refresh"],
            },
            "proof_debug" => {},
            "conversation_context" => {},
          },
          "human_sidechat" => { "content" => "Queued." },
          "user_message" => { "content" => "What are you doing?" },
        },
        idle_poll,
      ],
      "final_response" => idle_poll,
      "session" => {
        "conversation_supervision_session" => {
          "supervision_session_id" => "22222222-2222-2222-2222-222222222222",
        },
      },
    }

    markdown = Acceptance::ConversationArtifacts.supervision_status_markdown(supervision_trace: supervision_trace)
    final_section = markdown.split("## Poll 2").last

    assert_includes markdown, "- Current focus: `none`"
    assert_includes final_section, "- Current focus: `no active work`"
    assert_includes final_section, "- Recent progress: `Started the preview server in /workspace/game-2048`"
    refute_includes final_section, "Fixing the existing app in /workspace/game-2048"
  end

  test "builds a replayable supervision evaluation bundle from the frozen trace" do
    supervision_trace = {
      "polls" => [
        {
          "machine_status" => {
            "overall_state" => "running",
            "primary_turn_todo_plan_view" => {
              "goal_summary" => "Rebuild supervision around the active plan item.",
              "current_item_key" => "rewrite-prompt-payload",
              "current_item" => {
                "title" => "Rewrite the supervision prompt payload",
                "status" => "in_progress",
              },
            },
            "turn_feed" => [
              {
                "event_kind" => "turn_todo_item_completed",
                "summary" => "Replace heuristic context facts completed.",
                "occurred_at" => Time.current.iso8601(6),
              },
            ],
            "conversation_context" => {
              "context_snippets" => [
                {
                  "excerpt" => "Sidechat should use the active plan item as the semantic anchor.",
                  "keywords" => %w[sidechat active plan item semantic anchor],
                },
              ],
            },
            "runtime_evidence" => {
              "active_command" => {
                "cwd" => "/workspace/core_matrix",
                "command_preview" => "bin/rails test",
              },
            },
          },
        },
      ],
      "final_response" => {
        "machine_status" => {
          "overall_state" => "running",
        },
      },
    }

    bundle = Acceptance::ConversationArtifacts.supervision_eval_bundle(
      supervision_trace: supervision_trace,
      questions: ["What are you doing now?"]
    )

    assert_equal "running", bundle.dig("machine_status", "overall_state")
    assert_equal "Rewrite the supervision prompt payload",
      bundle.dig("primary_turn_todo_plan", "current_item", "title")
    assert_equal ["What are you doing now?"], bundle.fetch("questions")
    assert_equal ["Sidechat should use the active plan item as the semantic anchor."],
      bundle.fetch("context_snippets").map { |snippet| snippet.fetch("excerpt") }
  end
end
