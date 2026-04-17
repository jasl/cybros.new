require "test_helper"
require "tmpdir"

class Memory::StoreTest < ActiveSupport::TestCase
  test "builds a combined summary payload from root memory and conversation summary" do
    Dir.mktmpdir("nexus-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("MEMORY.md").write("Root memory\n")
      summary_path = root.join(".nexus", "conversations", "conversation-1", "context", "summary.md")
      FileUtils.mkdir_p(summary_path.dirname)
      summary_path.write("Session summary\n")

      payload = Memory::Store.new(
        workspace_root: workspace_root,
        conversation_id: "conversation-1"
      ).summary_payload

      assert_equal "Root memory\n", payload.fetch("root_memory")
      assert_equal "Session summary\n", payload.fetch("session_summary")
      assert_includes payload.fetch("summary"), "Root memory"
      assert_includes payload.fetch("summary"), "Session summary"
    end
  end
end
