require "test_helper"

class Turns::EditTailInputTest < ActiveSupport::TestCase
  test "creates a new selected input variant without mutating historical rows" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    ),
      content: "Original input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Old output")

    edited = Turns::EditTailInput.call(
      turn: turn,
      content: "Edited input"
    )

    assert_equal turn.id, edited.id
    assert_equal "Edited input", edited.selected_input_message.content
    assert_equal 1, edited.selected_input_message.variant_index
    assert_nil edited.selected_output_message
    assert_equal ["Original input", "Edited input"],
      UserMessage.where(turn: turn).order(:variant_index).pluck(:content)
  end

  test "rejects editing a non tail input without rollback or fork semantics" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    historical_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Historical input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    historical_turn.update!(lifecycle_state: "completed")
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      Turns::EditTailInput.call(turn: historical_turn, content: "Should fail")
    end
  end

  test "rejects editing tail input from an archived conversation" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Old output")
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::EditTailInput.call(turn: turn, content: "Should fail")
    end

    assert_includes error.record.errors[:lifecycle_state], "must belong to an active conversation to edit tail input"
  end

  test "rejects editing a source input required by an output anchored descendant" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Original output")
    Conversations::CreateBranch.call(
      parent: conversation,
      historical_anchor_message_id: output.id
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::EditTailInput.call(turn: turn, content: "Should fail")
    end

    assert_includes error.record.errors[:base], "cannot rewrite a fork-point input"
  end
end
