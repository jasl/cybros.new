require "test_helper"

class Fenix::Workspace::EnvOverlayTest < ActiveSupport::TestCase
  test "env overlays merge workspace and conversation files in precedence order" do
    Dir.mktmpdir do |tmpdir|
      root = Pathname.new(tmpdir)
      conversation_root = root.join(".fenix/conversations/conversation_123")
      FileUtils.mkdir_p(conversation_root)

      root.join(".env").write("SHARED=workspace\nOVERRIDE=workspace-env\n")
      root.join(".env.agent").write("ROOT_AGENT=1\nOVERRIDE=workspace-agent\n")
      conversation_root.join(".env").write("CONVERSATION=1\nOVERRIDE=conversation-env\n")
      conversation_root.join(".env.agent").write("CONVERSATION_AGENT=1\nOVERRIDE=conversation-agent\n")

      overlay = Fenix::Workspace::EnvOverlay.call(workspace_root: root, conversation_id: "conversation_123")

      assert_equal "workspace", overlay.fetch("SHARED")
      assert_equal "1", overlay.fetch("ROOT_AGENT")
      assert_equal "1", overlay.fetch("CONVERSATION")
      assert_equal "1", overlay.fetch("CONVERSATION_AGENT")
      assert_equal "conversation-agent", overlay.fetch("OVERRIDE")
    end
  end
end
