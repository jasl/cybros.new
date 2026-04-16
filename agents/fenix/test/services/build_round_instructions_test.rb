require "test_helper"

class BuildRoundInstructionsTest < ActiveSupport::TestCase
  test "builds a system prompt plus transcript without inferring durable state from transcript" do
    context = {
      "agent_context" => {
        "profile_key" => "pragmatic",
        "is_subagent" => false,
        "allowed_tool_names" => %w[exec_command browser_open],
      },
      "workspace_agent_context" => {
        "workspace_agent_id" => "workspace-agent-1",
        "global_instructions" => "Keep changes scoped to the mounted workspace agent.\n",
      },
      "runtime_context" => {
        "logical_work_id" => "prepare-round:workflow-node-1",
      },
      "provider_context" => {
        "provider_execution" => {
          "provider" => "openai",
        },
      },
      "transcript_messages" => [
        { "role" => "user", "content" => "Current todo: ship browser proof for 2048." },
      ],
      "work_context_view" => {
        "supervisor_guidance" => {
          "guidance_scope" => "session",
          "latest_guidance" => {
            "content" => "Stop and summarize the current blocker.",
            "delivered_at" => "2026-04-09T12:00:00Z",
          },
        },
      },
    }

    result = BuildRoundInstructions.call(context: context)

    assert_equal %w[exec_command browser_open], result.fetch("visible_tool_names")
    assert_equal "system", result.fetch("messages").first.fetch("role")
    assert_equal context.fetch("transcript_messages"), result.fetch("messages").drop(1)
    assert_includes result.fetch("messages").first.fetch("content"), "## Global Instructions"
    assert_includes result.fetch("messages").first.fetch("content"), "Keep changes scoped to the mounted workspace agent."
    assert_includes result.fetch("messages").first.fetch("content"), "Stop and summarize the current blocker."
    refute_includes result.fetch("messages").first.fetch("content"), "Current todo: ship browser proof for 2048."
    refute_includes result.fetch("messages").first.fetch("content"), "## Workspace Instructions"
  end

  test "uses the global-instructions fallback when no workspace agent context is provided" do
    context = {
      "agent_context" => {
        "profile_key" => "pragmatic",
        "is_subagent" => false,
        "allowed_tool_names" => %w[exec_command],
      },
      "runtime_context" => {
        "logical_work_id" => "prepare-round:workflow-node-1",
      },
      "provider_context" => {},
      "transcript_messages" => [
        { "role" => "user", "content" => "Continue." },
      ],
    }

    result = BuildRoundInstructions.call(context: context)

    assert_includes result.fetch("messages").first.fetch("content"), "No global instructions provided."
    refute_includes result.fetch("messages").first.fetch("content"), "## Specialist Routing"
    refute_includes result.fetch("messages").first.fetch("content"), "## Workspace Instructions"
  end

  test "falls back to the internal default profile when the requested interactive profile is unknown" do
    context = {
      "agent_context" => {
        "profile_key" => "missing-interactive-profile",
        "is_subagent" => false,
        "allowed_tool_names" => %w[exec_command],
      },
      "runtime_context" => {
        "logical_work_id" => "prepare-round:workflow-node-1",
      },
      "provider_context" => {},
      "transcript_messages" => [
        { "role" => "user", "content" => "Continue." },
      ],
    }

    result = BuildRoundInstructions.call(context: context)

    assert_includes result.fetch("messages").first.fetch("content"), "You are Fenix, the default fallback profile."
  end
end
