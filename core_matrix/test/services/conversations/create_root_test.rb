require "test_helper"

class Conversations::CreateRootTest < ActiveSupport::TestCase
  test "creates an active interactive root conversation with a self closure" do
    context = create_workspace_context!

    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    assert_equal context[:installation], conversation.installation
    assert_equal context[:workspace], conversation.workspace
    assert conversation.root?
    assert conversation.interactive?
    assert conversation.active?
    assert_nil conversation.parent_conversation
    assert_nil conversation.historical_anchor_message_id
    assert_equal [[conversation.id, conversation.id, 0]],
      ConversationClosure.where(descendant_conversation: conversation)
        .pluck(:ancestor_conversation_id, :descendant_conversation_id, :depth)
  end
end
