require "test_helper"
require "tmpdir"

class Fenix::Memory::StoreTest < ActiveSupport::TestCase
  test "builds a summary payload from workspace memory and conversation summary" do
    Dir.mktmpdir("fenix-workspace-") do |workspace_root|
      root = Pathname.new(workspace_root)
      root.join("MEMORY.md").write("Workspace memory\n")
      summary_root = root.join(".fenix", "conversations", "conversation-1", "context")
      FileUtils.mkdir_p(summary_root)
      summary_root.join("summary.md").write("Conversation summary\n")

      payload = Fenix::Memory::Store.new(
        workspace_root: workspace_root,
        conversation_id: "conversation-1"
      ).summary_payload

      assert_equal "Workspace memory\n", payload.fetch("root_memory")
      assert_equal "Conversation summary\n", payload.fetch("conversation_summary")
      assert_includes payload.fetch("summary"), "Workspace memory"
      assert_includes payload.fetch("summary"), "Conversation summary"
    end
  end
end
