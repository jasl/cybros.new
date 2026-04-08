require "test_helper"

class Fenix::Prompts::AssemblerTest < ActiveSupport::TestCase
  test "assembler prefers workspace overrides and conversation summaries without requiring workspace agents file" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)
      Fenix::Workspace::Bootstrap.call(workspace_root: root, conversation_id: "conversation_123")

      root.join("SOUL.md").write("workspace soul\n")
      root.join("MEMORY.md").write("workspace memory\n")
      root.join(".fenix/conversations/conversation_123/context/summary.md").write("conversation summary\n")

      assembled = Fenix::Prompts::Assembler.call(workspace_root: root, conversation_id: "conversation_123")

      assert_includes assembled.fetch("agent_prompt"), "Fenix"
      assert_equal "workspace soul\n", assembled.fetch("soul")
      assert_equal "workspace memory\n", assembled.fetch("memory")
      assert_equal "conversation summary\n", assembled.fetch("conversation_summary")
      refute root.join("AGENTS.md").exist?
      assert assembled.fetch("user").present?
    end
  end

  test "assembler includes operator prompt and structured operator state for the main profile only" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)
      Fenix::Workspace::Bootstrap.call(workspace_root: root, conversation_id: "conversation_123")
      root.join(".fenix/conversations/conversation_123/context/operator_state.json").write(
        JSON.pretty_generate(
          {
            "workspace" => { "highlights" => [{ "path" => "notes", "node_type" => "directory" }] },
            "process_runs" => [{ "process_run_id" => "process-run-1", "stdout_tail" => "x" * 4000 }],
          }
        )
      )

      assembled = Fenix::Prompts::Assembler.call(
        workspace_root: root,
        conversation_id: "conversation_123",
        profile: "main",
        is_subagent: false
      )
      subagent = Fenix::Prompts::Assembler.call(
        workspace_root: root,
        conversation_id: "conversation_123",
        profile: "researcher",
        is_subagent: true
      )

      assert_includes assembled.fetch("operator_prompt"), "resource-first operator surface"
      assert_equal "notes", assembled.dig("operator_state", "workspace", "highlights", 0, "path")
      refute_includes assembled.fetch("agent_prompt"), "x" * 100
      refute_includes assembled.fetch("operator_prompt"), "x" * 100
      assert assembled.fetch("operator_state").to_json.bytesize < 10_000
      refute subagent.key?("operator_prompt")
      refute subagent.key?("operator_state")
    end
  end
end
