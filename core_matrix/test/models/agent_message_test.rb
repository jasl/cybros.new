require "test_helper"

class AgentMessageTest < ActiveSupport::TestCase
  test "requires agent output role and slot" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(workspace: context[:workspace]),
      content: "Hello",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    invalid = AgentMessage.new(
      installation: context[:installation],
      conversation: turn.conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Wrong shape"
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:role], "must be agent"
    assert_includes invalid.errors[:slot], "must be output"
  end
end
