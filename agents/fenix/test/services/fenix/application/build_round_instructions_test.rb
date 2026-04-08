require "test_helper"
require "tmpdir"

class Fenix::Application::BuildRoundInstructionsTest < ActiveSupport::TestCase
  test "builds a system prompt plus transcript without inferring durable state from transcript" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("AGENTS.md").write("Keep changes scoped to agents/fenix.\n")

      context = {
        "agent_context" => {
          "profile" => "main",
          "is_subagent" => false,
          "allowed_tool_names" => %w[exec_command browser_open],
        },
        "workspace_context" => {
          "workspace_root" => workspace_root,
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
            "guidance_scope" => "conversation",
            "latest_guidance" => {
              "content" => "Stop and summarize the current blocker.",
              "delivered_at" => "2026-04-09T12:00:00Z",
            },
          },
        },
      }

      result = Fenix::Application::BuildRoundInstructions.call(context: context)

      assert_equal %w[exec_command browser_open], result.fetch("visible_tool_names")
      assert_equal "system", result.fetch("messages").first.fetch("role")
      assert_equal context.fetch("transcript_messages"), result.fetch("messages").drop(1)
      assert_includes result.fetch("messages").first.fetch("content"), "Stop and summarize the current blocker."
      refute_includes result.fetch("messages").first.fetch("content"), "Current todo: ship browser proof for 2048."
      assert_includes result.fetch("messages").first.fetch("content"), "Keep changes scoped to agents/fenix."
    end
  end
end
