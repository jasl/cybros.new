require "test_helper"

class UserMessageTest < ActiveSupport::TestCase
  test "requires user input role and slot" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
    ),
      content: "Hello",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    invalid = UserMessage.new(
      installation: context[:installation],
      conversation: turn.conversation,
      turn: turn,
      role: "agent",
      slot: "output",
      variant_index: 1,
      content: "Wrong shape"
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:role], "must be user"
    assert_includes invalid.errors[:slot], "must be input"
  end
end
