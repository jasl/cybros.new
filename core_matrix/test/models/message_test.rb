require "test_helper"

class MessageTest < ActiveSupport::TestCase
  test "generates and resolves a public id" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    ),
      content: "Hello",
      agent_program_version: context[:agent_program_version],
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
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    ),
      content: "Hello",
      agent_program_version: context[:agent_program_version],
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
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    ),
      content: "Hello",
      agent_program_version: context[:agent_program_version],
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

  test "requires output provenance to point at a same turn input message" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    ),
      content: "Hello",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    output = AgentMessage.new(
      installation: context[:installation],
      conversation: turn.conversation,
      turn: turn,
      role: "agent",
      slot: "output",
      variant_index: 0,
      content: "Output",
      source_input_message: turn.selected_input_message
    )

    assert output.valid?
  end

  test "rejects source input provenance that points at an output message" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    ),
      content: "Hello",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Original output")

    invalid = AgentMessage.new(
      installation: context[:installation],
      conversation: turn.conversation,
      turn: turn,
      role: "agent",
      slot: "output",
      variant_index: 1,
      content: "Invalid output",
      source_input_message: output
    )

    assert_not invalid.valid?
    assert_includes invalid.errors[:source_input_message], "must be an input message from the same turn"
  end
end
