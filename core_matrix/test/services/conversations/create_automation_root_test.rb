require "test_helper"

class Conversations::CreateAutomationRootTest < ActiveSupport::TestCase
  test "creates an active automation root conversation" do
    context = create_workspace_context!

    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])

    assert_equal context[:installation], conversation.installation
    assert_equal context[:workspace], conversation.workspace
    assert conversation.root?
    assert conversation.automation?
    assert conversation.active?
    assert conversation.retained?
    assert_nil conversation.parent_conversation
    assert_nil conversation.historical_anchor_message_id
    assert_equal "root", conversation.canonical_store_reference.canonical_store_snapshot.snapshot_kind
  end
end
