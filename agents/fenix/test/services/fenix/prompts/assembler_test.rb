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
end
