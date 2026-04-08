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
      write_skill(
        root: system_root,
        name: "deploy-agent",
        description: "Deploy agents safely",
        body: "Use evidence-backed deploy steps."
      )

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

  test "builds the default catalog from the scoped repository roots" do
    with_skill_fixture_roots do |roots|
      workspace_root = roots.fetch(:home_root).join("workspace")
      FileUtils.mkdir_p(workspace_root)

      repository = Fenix::Skills::Repository.new(
        agent_program_id: "agent-program-1",
        user_id: "user-1",
        home_root: roots.fetch(:home_root),
        system_root: roots.fetch(:system_root),
        curated_root: roots.fetch(:curated_root)
      )
      write_skill(
        root: repository.live_root,
        name: "portable-notes",
        description: "Capture notes.",
        body: "Use portable notes."
      )

      previous_home_root = ENV["FENIX_HOME_ROOT"]
      ENV["FENIX_HOME_ROOT"] = roots.fetch(:home_root).to_s

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
              { "role" => "user", "content" => "Use $portable-notes" },
            ],
            "context_imports" => [],
          },
          "runtime_context" => {
            "agent_program_id" => "agent-program-1",
            "user_id" => "user-1",
          },
          "workspace_context" => {
            "workspace_root" => workspace_root.to_s,
          },
        },
        memory_store: Fenix::Memory::Store.new(workspace_root: workspace_root, conversation_id: "conversation-1")
      )

      assert_equal ["portable-notes"], context.dig("skill_context", "active_skill_names")
      assert_includes context.dig("skill_context", "active_skill_contents", 0), "Use portable notes."
    ensure
      ENV["FENIX_HOME_ROOT"] = previous_home_root
    end
  end

  test "raises a deterministic error when default skills resolution lacks scope ids" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      error = assert_raises(Fenix::Runtime::PayloadContext::MissingSkillsScopeError) do
        Fenix::Runtime::PayloadContext.call(
          payload: {
            "task" => {
              "workflow_node_id" => "workflow-node-1",
              "conversation_id" => "conversation-1",
              "turn_id" => "turn-1",
              "kind" => "turn_step",
            },
            "round_context" => {
              "messages" => [
                { "role" => "user", "content" => "Use $portable-notes" },
              ],
              "context_imports" => [],
            },
            "runtime_context" => {
              "agent_program_version_id" => "agent-program-version-1",
            },
            "workspace_context" => {
              "workspace_root" => workspace_root,
            },
          }
        )
      end

      assert_includes error.message, "agent_program_id"
      assert_includes error.message, "user_id"
    end
  end
end
