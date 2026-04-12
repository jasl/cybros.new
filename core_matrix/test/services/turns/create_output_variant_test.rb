require "test_helper"

class Turns::CreateOutputVariantTest < ActiveSupport::TestCase
  test "creates output variants with monotonically increasing indexes on the same turn" do
    context = create_workspace_context!
    turn = Turns::StartUserTurn.call(
      conversation: Conversations::CreateRoot.call(
        workspace: context[:workspace],
      ),
      content: "Input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    first_output = Turns::CreateOutputVariant.call(turn: turn, content: "First")
    second_output = Turns::CreateOutputVariant.call(turn: turn, content: "Second")

    assert_equal 0, first_output.variant_index
    assert_equal 1, second_output.variant_index
    assert_equal turn.selected_input_message, first_output.source_input_message
    assert_equal turn.selected_input_message, second_output.source_input_message
  end

  test "rejects source messages that are not input variants from the same turn" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    foreign_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Foreign input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    foreign_output = Turns::CreateOutputVariant.call(turn: foreign_turn, content: "Foreign output")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::CreateOutputVariant.call(
        turn: turn,
        content: "Invalid output",
        source_input_message: foreign_output
      )
    end

    assert_includes error.record.errors[:selected_input_message], "must be an input message from the same turn"
  end
end
