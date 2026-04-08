require "test_helper"

class Fenix::Workspace::BootstrapTest < ActiveSupport::TestCase
  test "bootstrap seeds fenix runtime directories without creating a workspace agents file" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      Fenix::Workspace::Bootstrap.call(workspace_root: root, conversation_id: "conversation_123")

      assert root.join(".fenix/memory/root.md").exist?
      assert root.join(".fenix/memory/daily").directory?
      assert root.join(".fenix/conversations/conversation_123/meta.json").exist?
      refute root.join("AGENTS.md").exist?

      metadata = JSON.parse(root.join(".fenix/conversations/conversation_123/meta.json").read)
      assert_equal "conversation_123", metadata.fetch("conversation_public_id")
    end
  end

  test "bootstrap namespaces conversation state under the deployment public id when provided" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)

      Fenix::Workspace::Bootstrap.call(
        workspace_root: root,
        conversation_id: "conversation_123",
        agent_program_version_id: "agent_program_version_123"
      )

      meta_path = root.join(".fenix/agent_program_versions/agent_program_version_123/conversations/conversation_123/meta.json")

      assert meta_path.exist?

      metadata = JSON.parse(meta_path.read)

      assert_equal "conversation_123", metadata.fetch("conversation_public_id")
      assert_equal "agent_program_version_123", metadata.fetch("agent_program_version_id")
    end
  end
end
