require "test_helper"
require Rails.root.join("../acceptance/lib/turn_runtime_transcript")

class AcceptanceTurnRuntimeTranscriptTest < ActiveSupport::TestCase
  test "builds a readable timeline with actor lanes and phase sections" do
    report = Acceptance::TurnRuntimeTranscript.build(
      conversation_id: "conv_123",
      turn_id: "turn_123",
      phase_events: [
        {
          "timestamp" => "2026-04-06T08:48:21Z",
          "phase" => "attempt_started",
          "attempt_no" => 1,
          "max_turn_attempts" => 3,
        },
        {
          "timestamp" => "2026-04-06T08:57:27Z",
          "phase" => "host_validation_complete",
          "attempt_no" => 1,
          "npm_test_passed" => true,
          "npm_build_passed" => true,
          "preview_reachable" => true,
          "playwright_verification_passed" => true,
        },
        {
          "timestamp" => "2026-04-06T08:49:20Z",
          "phase" => "supervision_progress",
          "poll_index" => 2,
          "overall_state" => "working",
          "current_focus_summary" => "Applying merge logic to the board reducer",
          "recent_progress_summary" => "Finished wiring keyboard controls",
        },
      ],
      workflow_node_events: [
        {
          "workflow_node_key" => "provider_round_3_tool_1",
          "event_kind" => "node_completed",
          "occurred_at" => "2026-04-06T08:49:10Z",
          "node_type" => "tool_call",
          "payload" => { "tool_name" => "workspace_write" },
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
          "tool_name" => "workspace_tree",
          "status" => "succeeded",
          "started_at" => "2026-04-06T08:48:31Z",
          "finished_at" => "2026-04-06T08:48:32Z",
          "request_payload" => { "arguments" => { "path" => "/workspace" } },
          "response_payload" => {},
          "agent_task_run_id" => nil,
        },
        {
          "tool_name" => "subagent_spawn",
          "status" => "succeeded",
          "started_at" => "2026-04-06T08:49:00Z",
          "finished_at" => "2026-04-06T08:49:01Z",
          "request_payload" => { "arguments" => { "profile_key" => "researcher" } },
          "response_payload" => { "subagent_session_id" => "sub_1", "profile_key" => "researcher" },
          "agent_task_run_id" => nil,
        },
      ],
      command_runs: [
        {
          "command_line" => "cd /workspace/game-2048 && npm test && npm run build",
          "lifecycle_state" => "completed",
          "started_at" => "2026-04-06T08:50:00Z",
          "ended_at" => "2026-04-06T08:50:30Z",
          "tool_invocation_id" => "tool_1",
        },
        {
          "command_line" => "cd /workspace/game-2048 && npm run preview",
          "lifecycle_state" => "running",
          "started_at" => "2026-04-06T08:50:31Z",
          "ended_at" => "2026-04-06T08:50:32Z",
          "tool_invocation_id" => "tool_1",
        },
      ],
      process_runs: [],
      subagent_sessions: [
        {
          "subagent_session_id" => "sub_1",
          "profile_key" => "researcher",
          "observed_status" => "completed",
          "created_at" => "2026-04-06T08:49:00Z",
          "updated_at" => "2026-04-06T08:49:45Z",
        },
      ],
      subagent_runtime_snapshots: [
        {
          "subagent_session_id" => "sub_1",
          "profile_key" => "researcher",
          "usage_events" => [
            {
              "occurred_at" => "2026-04-06T08:49:05Z",
              "workflow_node_key" => "provider_round_1",
              "output_tokens" => 42,
              "input_tokens" => 512,
              "provider_handle" => "openrouter",
              "model_ref" => "openai-gpt-5.4",
            },
          ],
          "tool_invocations" => [
            {
              "tool_name" => "workspace_tree",
              "status" => "succeeded",
              "started_at" => "2026-04-06T08:49:06Z",
              "finished_at" => "2026-04-06T08:49:07Z",
              "request_payload" => { "arguments" => { "path" => "/workspace/game-2048" } },
              "response_payload" => {},
            },
          ],
          "command_runs" => [
            {
              "command_line" => "cd /workspace/game-2048 && npm test",
              "lifecycle_state" => "completed",
              "started_at" => "2026-04-06T08:49:08Z",
              "ended_at" => "2026-04-06T08:49:11Z",
            },
          ],
          "process_runs" => [],
        },
      ],
      agent_task_runs: [],
      supervision_trace: {
        "final_response" => {
          "machine_status" => {
            "overall_state" => "idle",
            "current_focus_summary" => "idle after finishing the turn",
          },
        },
      },
      summary: {
        "benchmark_outcome" => "pass_clean",
        "workload_outcome" => "complete",
        "system_behavior_outcome" => "healthy",
      }
    )

    assert_equal "turn_123", report.fetch("turn_id")
    assert_equal true, report.dig("counts", "has_subagent_lane")
    assert_includes report.fetch("lanes").map { |lane| lane.fetch("actor_label") }, "main"
    assert_includes report.fetch("lanes").map { |lane| lane.fetch("actor_label") }, "researcher#1"
    assert_includes report.fetch("lanes").map { |lane| lane.fetch("actor_label") }, "host"

    summaries = report.fetch("timeline").map { |entry| entry.fetch("summary") }
    assert_includes summaries, "Started attempt 1 of 3"
    assert_includes summaries, "Supervisor checkpoint: Applying merge logic to the board reducer"
    assert_includes summaries, "Ran the test-and-build check in /workspace/game-2048"
    assert_includes summaries, "Starting the preview server in /workspace/game-2048"
    assert_includes summaries, "Inspected the workspace tree"
    assert_includes summaries, "Spawned subagent researcher#1"
    assert_includes summaries, "researcher#1 completed its assigned work"
    assert_includes summaries, "Host validation passed: tests, build, preview, and Playwright"

    markdown = Acceptance::TurnRuntimeTranscript.to_markdown(report)

    assert_includes markdown, "# Turn Runtime Transcript"
    assert_includes markdown, "## Plan"
    assert_includes markdown, "## Build"
    assert_includes markdown, "## Validate"
    assert_includes markdown, "[researcher#1]"
    assert_includes markdown, "[supervisor]"
    assert_includes markdown, "[researcher#1] Inspected the workspace tree"
    assert_includes markdown, "[researcher#1] Ran the test run in /workspace/game-2048"
    assert_includes markdown, "[main] Ran the test-and-build check in /workspace/game-2048"
    assert_includes markdown, "[main] Starting the preview server in /workspace/game-2048"
    assert_includes markdown, "Host validation passed: tests, build, preview, and Playwright"
  end
end
