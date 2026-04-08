require "test_helper"
require "tmpdir"

class Fenix::Runtime::PrepareRoundTest < ActiveSupport::TestCase
  test "prepare_round returns layered system instructions and visible tool names" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("AGENTS.md").write("Stay inside agents/fenix unless the task explicitly spans projects.\n")

      response = Fenix::Runtime::PrepareRound.call(
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
                "guidance_scope" => "conversation",
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
            "agent_program_version_id" => "agent-program-version-1",
            "logical_work_id" => "prepare-round:workflow-node-1",
          },
          "workspace_context" => {
            "workspace_root" => workspace_root,
          },
        }
      )

      assert_equal "ok", response.fetch("status")
      assert_equal %w[compact_context exec_command browser_open], response.fetch("visible_tool_names")
      assert_equal "system", response.fetch("messages").first.fetch("role")
      assert_equal "user", response.fetch("messages").second.fetch("role")
      assert_includes response.fetch("messages").first.fetch("content"), "## Code-Owned Base"
      assert_includes response.fetch("messages").first.fetch("content"), "## Role Overlay"
      assert_includes response.fetch("messages").first.fetch("content"), "## Workspace Instructions"
      assert_includes response.fetch("messages").first.fetch("content"), "## Supervisor Guidance"
      assert_includes response.fetch("messages").first.fetch("content"), "## CoreMatrix Durable State"
      assert_includes response.fetch("messages").first.fetch("content"), "## Execution-Local Fenix Context"
      assert_includes response.fetch("messages").first.fetch("content"), "Stay inside agents/fenix unless the task explicitly spans projects."
      assert_includes response.fetch("messages").first.fetch("content"), "Stop and summarize the current blocker before coding."
      assert_includes response.fetch("messages").first.fetch("content"), "\"goal\": \"Ship the 2048 capstone\""
      assert_equal "Build the 2048 acceptance path.", response.fetch("messages").second.fetch("content")
    end
  end
end
