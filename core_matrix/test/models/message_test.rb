require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Hello",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message

    assert message.public_id.present?
    assert_equal message, Message.find_by_public_id!(message.public_id)
  end

  test "restricts STI persistence to transcript bearing subclasses" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Hello",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    message = Message.new(
      installation: context[:installation],
      conversation: turn.conversation,
      turn: turn,
      type: "Message",
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "raw"
    )

    assert_not message.valid?
    assert_includes message.errors[:type], "must be a transcript-bearing subclass"
  end

  test "enforces unique variants within one turn and slot" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    ),
      content: "Hello",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    duplicate = UserMessage.new(
      installation: context[:installation],
      conversation: turn.conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: "Hello again"
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:variant_index], "has already been taken"
  end
end
