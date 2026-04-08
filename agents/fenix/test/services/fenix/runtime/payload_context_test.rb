require "test_helper"
require "tmpdir"

class Fenix::Runtime::PayloadContextTest < ActiveSupport::TestCase
  test "hydrates memory and lazy skill context from workspace files and transcript references" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("MEMORY.md").write("Workspace memory\n")
      summary_root = root.join(".fenix", "conversations", "conversation-1", "context")
      FileUtils.mkdir_p(summary_root)
      summary_root.join("summary.md").write("Conversation summary\n")

      skills_root = root.join("skills")
      system_root = skills_root.join(".system")
      live_root = skills_root.join("live")
      curated_root = skills_root.join(".curated")
      write_skill(system_root, "deploy-agent", "Deploy agents safely", "Use evidence-backed deploy steps.")

      context = Fenix::Runtime::PayloadContext.call(
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
            "agent_program_version_id" => "agent-program-version-1",
          },
          "workspace_context" => {
            "workspace_root" => workspace_root,
          },
        },
        memory_store: Fenix::Memory::Store.new(workspace_root: workspace_root, conversation_id: "conversation-1"),
        skills_catalog: Fenix::Skills::Catalog.new(
          system_root: system_root,
          live_root: live_root,
          curated_root: curated_root
        )
      )

      assert_includes context.dig("memory_context", "summary"), "Workspace memory"
      assert_includes context.dig("memory_context", "summary"), "Conversation summary"
      assert_equal ["deploy-agent"], context.dig("skill_context", "active_skill_names")
      assert_includes context.dig("skill_context", "active_skill_contents", 0), "Use evidence-backed deploy steps."
    end
  end

  private

  def write_skill(root, name, description, body)
    skill_root = root.join(name)
    FileUtils.mkdir_p(skill_root)
    skill_root.join("SKILL.md").write(
      <<~MARKDOWN
        ---
        name: #{name}
        description: #{description}
        ---

        #{body}
      MARKDOWN
    )
  end
end
