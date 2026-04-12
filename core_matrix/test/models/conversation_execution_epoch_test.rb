require "test_helper"

class ConversationExecutionEpochTest < ActiveSupport::TestCase
  test "requires sequence uniqueness within one conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    duplicate = ConversationExecutionEpoch.new(
      installation: conversation.installation,
      conversation: conversation,
      sequence: conversation.current_execution_epoch.sequence,
      execution_runtime: conversation.current_execution_runtime,
      lifecycle_state: "active",
      continuity_payload: {}
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:sequence], "has already been taken"
  end

  test "requires source epoch to belong to the same conversation" do
    context = create_workspace_context!
    first = Conversations::CreateRoot.call(workspace: context[:workspace])
    second = Conversations::CreateRoot.call(workspace: context[:workspace])

    epoch = ConversationExecutionEpoch.new(
      installation: second.installation,
      conversation: second,
      sequence: 2,
      execution_runtime: second.current_execution_runtime,
      source_execution_epoch: first.current_execution_epoch,
      lifecycle_state: "active",
      continuity_payload: {}
    )

    assert_not epoch.valid?
    assert_includes epoch.errors[:source_execution_epoch], "must belong to the same conversation"
  end
end
