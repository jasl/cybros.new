require "test_helper"

class ConversationRuntime::BuildTurnEventStreamTest < ActiveSupport::TestCase
  test "builds an ordered runtime event stream with generic safe summaries and exact refs" do
    report = ConversationRuntime::BuildTurnEventStream.call(
      conversation_id: "conv_123",
      turn_id: "turn_123",
      phase_events: [],
      workflow_node_events: [
        {
          "created_at" => "2026-04-06T08:49:10Z",
          "workflow_run_public_id" => "wr_public_123",
          "workflow_node_public_id" => "node_public_123",
          "workflow_node_key" => "provider_round_3_tool_1",
          "workflow_node_ordinal" => 4,
          "event_kind" => "node_completed",
          "node_type" => "tool_call",
          "payload" => {
            "state" => "completed",
            "tool_invocation_id" => "tool_public_123",
          },
        },
      ],
      usage_events: [
        {
          "occurred_at" => "2026-04-06T08:48:30Z",
          "workflow_node_key" => "provider_round_2",
          "output_tokens" => 145,
          "input_tokens" => 6914,
          "provider_handle" => "openrouter",
          "model_ref" => "openai-gpt-5.4",
        },
      ],
      tool_invocations: [
        {
          "tool_invocation_id" => "tool_public_123",
          "tool_name" => "workspace_tree",
          "status" => "succeeded",
          "started_at" => "2026-04-06T08:48:31Z",
          "finished_at" => "2026-04-06T08:48:32Z",
          "request_payload" => { "arguments" => { "path" => "/workspace/game-2048" } },
          "response_payload" => {},
          "agent_task_run_id" => nil,
        },
      ],
      command_runs: [
        {
          "command_run_public_id" => "cmd_public_123",
          "command_line" => "cd /workspace/game-2048 && npm test && npm run build",
          "lifecycle_state" => "completed",
          "started_at" => "2026-04-06T08:50:00Z",
          "ended_at" => "2026-04-06T08:50:30Z",
          "tool_invocation_id" => "tool_public_123",
          "workflow_node_key" => "provider_round_3_tool_1",
        },
      ],
      process_runs: [
        {
          "process_run_public_id" => "proc_public_123",
          "command_line" => "cd /workspace/game-2048 && npm run preview",
          "lifecycle_state" => "running",
          "started_at" => "2026-04-06T08:50:31Z",
          "ended_at" => "2026-04-06T08:50:32Z",
          "tool_invocation_id" => "tool_public_123",
        },
      ],
      subagent_connections: [],
      subagent_runtime_snapshots: [],
      agent_task_runs: [],
      supervision_trace: {},
      summary: {}
    )

    timeline = report.fetch("timeline")
    test_and_build_event = timeline.find { |entry| entry["command_run_public_id"] == "cmd_public_123" }
    preview_event = timeline.find { |entry| entry["process_run_public_id"] == "proc_public_123" }

    assert_equal "turn_123", report.fetch("turn_id")
    assert_operator timeline.length, :>=, 4

    assert_equal "command_activity", test_and_build_event.fetch("family")
    assert_equal "command_completed", test_and_build_event.fetch("kind")
    assert_equal "A shell command finished in /workspace/game-2048", test_and_build_event.fetch("summary")
    assert_equal "provider_round_3_tool_1", test_and_build_event.fetch("workflow_node_key")
    assert_equal "tool_public_123", test_and_build_event.fetch("tool_invocation_public_id")

    assert_equal "process_activity", preview_event.fetch("family")
    assert_equal "process_started", preview_event.fetch("kind")
    assert_equal "A process is running in /workspace/game-2048", preview_event.fetch("summary")

    refute timeline.any? { |entry| entry.fetch("summary").match?(/provider round|provider_round_|command_run_wait/) }
    refute timeline.any? { |entry| entry["detail"].to_s.match?(/workspace_tree|command_run_wait|tool `workspace/i) }
  end

  test "uses referenced command metadata for write_stdin tool activity events without guessing business semantics" do
    report = ConversationRuntime::BuildTurnEventStream.call(
      conversation_id: "conv_123",
      turn_id: "turn_123",
      phase_events: [],
      workflow_node_events: [],
      usage_events: [],
      tool_invocations: [
        {
          "tool_invocation_id" => "tool_public_123",
          "tool_name" => "write_stdin",
          "status" => "succeeded",
          "started_at" => "2026-04-06T08:48:31Z",
          "finished_at" => "2026-04-06T08:48:32Z",
          "request_payload" => {
            "arguments" => {
              "command_run_id" => "cmd_public_123",
            },
          },
          "response_payload" => {
            "session_closed" => true,
            "command_run_id" => "cmd_public_123",
          },
          "agent_task_run_id" => nil,
        },
      ],
      command_runs: [
        {
          "command_run_public_id" => "cmd_public_123",
          "command_line" => "cd /workspace/game-2048 && npm install",
          "lifecycle_state" => "completed",
          "started_at" => "2026-04-06T08:48:00Z",
          "ended_at" => "2026-04-06T08:48:30Z",
          "tool_invocation_id" => "tool_public_122",
          "workflow_node_key" => "provider_round_2_tool_1",
        },
      ],
      process_runs: [],
      subagent_connections: [],
      subagent_runtime_snapshots: [],
      agent_task_runs: [],
      supervision_trace: {},
      summary: {}
    )

    event = report.fetch("timeline").find { |entry| entry["tool_invocation_public_id"] == "tool_public_123" }

    assert_equal "A shell command finished in /workspace/game-2048", event.fetch("summary")
    refute_match(/Sent input to the running command|Respond to/i, event.to_json)
  end
end
