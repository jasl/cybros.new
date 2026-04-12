require "test_helper"

class Workbench::SendMessageTest < ActiveSupport::TestCase
  test "appends a new user turn to an existing conversation without creating a workspace or conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    result = nil

    assert_no_difference(["UserAgentBinding.count", "Workspace.count", "Conversation.count"]) do
      assert_difference(["Turn.count", "Message.count"], +1) do
        result = Workbench::SendMessage.call(
          conversation: conversation,
          content: "Follow up"
        )
      end
    end

    assert_equal conversation, result.conversation
    assert_equal "Follow up", result.message.content
    assert_equal result.turn, result.message.turn
  end
end
