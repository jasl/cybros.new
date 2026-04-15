require "test_helper"

class Requests::PrepareRoundTest < ActiveSupport::TestCase
  test "prepare_round returns layered system instructions and visible tool names" do
    response = Requests::PrepareRound.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "round_context" => {
          "messages" => [
            { "role" => "user", "content" => "Build the 2048 acceptance path." },
          ],
          "context_imports" => [],
          "work_context_view" => {
            "goal" => "Ship the 2048 capstone",
            "supervisor_guidance" => {
              "guidance_scope" => "session",
              "latest_guidance" => {
                "content" => "Stop and summarize the current blocker before coding.",
                "delivered_at" => "2026-04-09T12:00:00Z",
              },
            },
            "plan" => [
              { "step" => "Implement runtime tools", "status" => "done" },
              { "step" => "Build prompt pipeline", "status" => "in_progress" },
            ],
          },
        },
        "agent_context" => {
          "profile" => "main",
          "allowed_tool_names" => %w[compact_context exec_command browser_open],
        },
        "provider_context" => {
          "provider_execution" => { "provider" => "openai" },
          "model_context" => { "model_slug" => "gpt-5.4" },
        },
        "runtime_context" => {
          "agent_definition_version_id" => "agent-definition-version-1",
          "logical_work_id" => "prepare-round:workflow-node-1",
        },
        "workspace_agent_context" => {
          "workspace_agent_id" => "workspace-agent-1",
          "global_instructions" => "Stay inside the mounted workspace agent scope.\n",
        },
      }
    )

    assert_equal "ok", response.fetch("status")
    assert_equal %w[compact_context exec_command browser_open], response.fetch("visible_tool_names")
    assert_equal "system", response.fetch("messages").first.fetch("role")
    assert_equal "user", response.fetch("messages").second.fetch("role")
    assert_includes response.fetch("messages").first.fetch("content"), "## Code-Owned Base"
    assert_includes response.fetch("messages").first.fetch("content"), "## Role Overlay"
    assert_includes response.fetch("messages").first.fetch("content"), "## Global Instructions"
    assert_includes response.fetch("messages").first.fetch("content"), "## Supervisor Guidance"
    assert_includes response.fetch("messages").first.fetch("content"), "## CoreMatrix Durable State"
    assert_includes response.fetch("messages").first.fetch("content"), "## Execution-Local Fenix Context"
    assert_includes response.fetch("messages").first.fetch("content"), "Stay inside the mounted workspace agent scope."
    assert_includes response.fetch("messages").first.fetch("content"), "Stop and summarize the current blocker before coding."
    assert_includes response.fetch("messages").first.fetch("content"), "\"goal\": \"Ship the 2048 capstone\""
    refute_includes response.fetch("messages").first.fetch("content"), "## Workspace Instructions"
    assert_equal "Build the 2048 acceptance path.", response.fetch("messages").second.fetch("content")
  end

  test "prepare_round uses explicit runtime-provided memory and skill contexts" do
    response = Requests::PrepareRound.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "round_context" => {
          "messages" => [
            { "role" => "user", "content" => "What should we remember before continuing?" },
          ],
          "context_imports" => [],
        },
        "runtime_context" => {
          "agent_definition_version_id" => "agent-definition-version-1",
        },
        "workspace_agent_context" => {
          "workspace_agent_id" => "workspace-agent-1",
          "global_instructions" => "Stay inside the mounted workspace agent scope.\n",
        },
        "memory_context" => {
          "summary" => "Runtime memory: Docker daemon was flaky earlier.",
        },
        "skill_context" => {
          "active_skill_names" => ["portable-notes"],
          "active_skill_contents" => ["Use portable notes before you summarize."],
        },
      }
    )

    prompt = response.fetch("messages").first.fetch("content")

    assert_equal "ok", response.fetch("status")
    assert_includes prompt, "Stay inside the mounted workspace agent scope."
    assert_includes prompt, "Runtime memory: Docker daemon was flaky earlier."
    assert_includes prompt, "Use portable notes before you summarize."
  end

  test "prepare_round does not resolve runtime-local skills when they are not provided" do
    response = Requests::PrepareRound.call(
      payload: {
        "task" => {
          "workflow_node_id" => "workflow-node-1",
          "conversation_id" => "conversation-1",
          "turn_id" => "turn-1",
          "kind" => "turn_step",
        },
        "round_context" => {
          "messages" => [
            { "role" => "user", "content" => "Please use $portable-notes before replying." },
          ],
          "context_imports" => [],
        },
        "runtime_context" => {},
      }
    )

    assert_equal "ok", response.fetch("status")
    refute_includes response.fetch("messages").first.fetch("content"), "Use portable notes before you summarize."
  end
end
