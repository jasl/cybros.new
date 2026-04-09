require "test_helper"
require "tmpdir"

class Fenix::Agent::Program::PrepareRoundTest < ActiveSupport::TestCase
  test "prepare_round returns layered system instructions and visible tool names" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("AGENTS.md").write("Stay inside agents/fenix unless the task explicitly spans projects.\n")

      response = Fenix::Agent::Program::PrepareRound.call(
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

  test "prepare_round loads active skill overlays through the agent skills repository" do
    Dir.mktmpdir("fenix-skills-home-") do |home_root|
      system_root = Pathname.new(home_root).join("skills", ".system")
      live_root = Pathname.new(home_root).join("skills-scopes", "agent-program-1", "user-1", "live")
      skill_root = live_root.join("portable-notes")
      FileUtils.mkdir_p(skill_root)
      skill_root.join("SKILL.md").write(<<~MARKDOWN)
        ---
        name: portable-notes
        description: Capture portable notes.
        ---

        Use portable notes before you summarize.
      MARKDOWN

      previous_home_root = ENV["FENIX_HOME_ROOT"]
      ENV["FENIX_HOME_ROOT"] = home_root

      response = Fenix::Agent::Program::PrepareRound.call(
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
          "runtime_context" => {
            "agent_program_id" => "agent-program-1",
            "user_id" => "user-1",
          },
        }
      )

      assert_equal "ok", response.fetch("status")
      assert_includes response.fetch("messages").first.fetch("content"), "Use portable notes before you summarize."
    ensure
      ENV["FENIX_HOME_ROOT"] = previous_home_root
    end
  end

  test "prepare_round raises a deterministic scope error when a requested skill lacks runtime scope ids" do
    error = assert_raises(Fenix::Agent::Skills::Repository::MissingScopeError) do
      Fenix::Agent::Program::PrepareRound.call(
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
          "runtime_context" => {
            "agent_program_version_id" => "agent-program-version-1",
          },
        }
      )
    end

    assert_includes error.message, "agent_program_id"
    assert_includes error.message, "user_id"
  end
end
