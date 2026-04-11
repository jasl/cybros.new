require "test_helper"
require "tmpdir"

class Nexus::Shared::PayloadContextTest < ActiveSupport::TestCase
  test "hydrates memory and preserves an explicit skill context" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("MEMORY.md").write("Workspace memory\n")
      summary_root = root.join(".nexus", "conversations", "conversation-1", "context")
      FileUtils.mkdir_p(summary_root)
      summary_root.join("summary.md").write("Session summary\n")

      context = Nexus::Shared::PayloadContext.call(
        payload: {
          "task" => {
            "workflow_node_id" => "workflow-node-1",
            "conversation_id" => "conversation-1",
            "turn_id" => "turn-1",
            "kind" => "turn_step",
          },
          "round_context" => {
            "messages" => [
              { "role" => "user", "content" => "Use $deploy-agent before delivery." },
            ],
            "context_imports" => [],
          },
          "agent_context" => {
            "profile" => "main",
            "allowed_tool_names" => %w[compact_context],
          },
          "provider_context" => {},
          "runtime_context" => {
            "agent_version_id" => "agent-snapshot-1",
          },
          "workspace_context" => {
            "workspace_root" => workspace_root,
          },
        },
        memory_store: Nexus::Agent::Memory::Store.new(workspace_root: workspace_root, conversation_id: "conversation-1"),
        defaults: {
          "skill_context" => {
            "active_skill_names" => ["deploy-agent"],
            "active_skill_contents" => ["Use evidence-backed deploy steps."],
          },
        }
      )

      assert_includes context.dig("memory_context", "summary"), "Workspace memory"
      assert_includes context.dig("memory_context", "summary"), "Session summary"
      assert_equal ["deploy-agent"], context.dig("skill_context", "active_skill_names")
      assert_includes context.dig("skill_context", "active_skill_contents", 0), "Use evidence-backed deploy steps."
    end
  end
end
