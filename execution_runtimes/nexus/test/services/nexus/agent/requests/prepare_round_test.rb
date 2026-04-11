require "test_helper"
require "tmpdir"

class Nexus::Agent::Requests::PrepareRoundTest < ActiveSupport::TestCase
  test "prepare_round returns layered system instructions and visible tool names" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("AGENTS.md").write("Stay inside agents/nexus unless the task explicitly spans projects.\n")

      response = Nexus::Agent::Requests::PrepareRound.call(
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
            "agent_version_id" => "agent-snapshot-1",
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
      assert_includes response.fetch("messages").first.fetch("content"), "## Execution-Local Nexus Context"
      assert_includes response.fetch("messages").first.fetch("content"), "Stay inside agents/nexus unless the task explicitly spans projects."
      assert_includes response.fetch("messages").first.fetch("content"), "Stop and summarize the current blocker before coding."
      assert_includes response.fetch("messages").first.fetch("content"), "\"goal\": \"Ship the 2048 capstone\""
      assert_equal "Build the 2048 acceptance path.", response.fetch("messages").second.fetch("content")
    end
  end

  test "prepare_round loads active skill overlays through the agent skills repository" do
    Dir.mktmpdir("nexus-skills-home-") do |home_root|
      system_root = Pathname.new(home_root).join("skills", ".system")
      live_root = Pathname.new(home_root).join("skills-scopes", "agent-1", "user-1", "live")
      skill_root = live_root.join("portable-notes")
      FileUtils.mkdir_p(skill_root)
      skill_root.join("SKILL.md").write(<<~MARKDOWN)
        ---
        name: portable-notes
        description: Capture portable notes.
        ---

        Use portable notes before you summarize.
      MARKDOWN

      previous_home_root = ENV["NEXUS_HOME_ROOT"]
      ENV["NEXUS_HOME_ROOT"] = home_root

      response = Nexus::Agent::Requests::PrepareRound.call(
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
            "agent_id" => "agent-1",
            "user_id" => "user-1",
          },
        }
      )

      assert_equal "ok", response.fetch("status")
      assert_includes response.fetch("messages").first.fetch("content"), "Use portable notes before you summarize."
    ensure
      ENV["NEXUS_HOME_ROOT"] = previous_home_root
    end
  end

  test "prepare_round recalls root memory and conversation summary into the system prompt" do
    Dir.mktmpdir("nexus-memory-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("MEMORY.md").write("Project memory: prefer acceptance-driven validation.\n")
      summary_path = root.join(".nexus", "conversations", "conversation-1", "context", "summary.md")
      FileUtils.mkdir_p(summary_path.dirname)
      summary_path.write("Session memory: Docker daemon was flaky earlier.\n")

      response = Nexus::Agent::Requests::PrepareRound.call(
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
            "agent_version_id" => "agent-snapshot-1",
          },
          "workspace_context" => {
            "workspace_root" => workspace_root,
          },
        }
      )

      prompt = response.fetch("messages").first.fetch("content")

      assert_equal "ok", response.fetch("status")
      assert_includes prompt, "## Execution-Local Nexus Context"
      assert_includes prompt, "Project memory: prefer acceptance-driven validation."
      assert_includes prompt, "Session memory: Docker daemon was flaky earlier."
    end
  end

  test "prepare_round raises a deterministic scope error when a requested skill lacks runtime scope ids" do
    error = assert_raises(Nexus::Agent::Skills::Repository::MissingScopeError) do
      Nexus::Agent::Requests::PrepareRound.call(
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
            "agent_version_id" => "agent-snapshot-1",
          },
        }
      )
    end

    assert_includes error.message, "agent_id"
    assert_includes error.message, "user_id"
  end
end
