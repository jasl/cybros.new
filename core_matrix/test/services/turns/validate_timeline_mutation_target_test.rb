require "test_helper"

class Turns::ValidateTimelineMutationTargetTest < ActiveSupport::TestCase
  test "returns the turn when timeline mutation is allowed and the turn is uninterrupted" do
    turn = build_completed_turn_with_output!

    validated = Turns::ValidateTimelineMutationTarget.call(
      turn: turn,
      retained_message: "must be retained before rewriting output",
      active_message: "must belong to an active conversation to rewrite output",
      closing_message: "must not rewrite output while close is in progress",
      interrupted_message: "must not rewrite output after turn interruption"
    )

    assert_same turn, validated
  end

  test "rejects timeline mutation when the conversation is pending delete" do
    turn = build_completed_turn_with_output!
    turn.conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateTimelineMutationTarget.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      )
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:deletion_state], "must be retained before rewriting output"
  end

  test "rejects timeline mutation when the conversation is archived" do
    turn = build_completed_turn_with_output!
    turn.conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateTimelineMutationTarget.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      )
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:lifecycle_state], "must belong to an active conversation to rewrite output"
  end

  test "rejects timeline mutation while close is in progress" do
    turn = build_completed_turn_with_output!
    ConversationCloseOperation.create!(
      installation: turn.installation,
      conversation: turn.conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateTimelineMutationTarget.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      )
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:base], "must not rewrite output while close is in progress"
  end

  test "uses the provided locked conversation while validating timeline mutation" do
    turn = build_completed_turn_with_output!
    locked_conversation = turn.conversation.reload
    ConversationCloseOperation.create!(
      installation: locked_conversation.installation,
      conversation: locked_conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateTimelineMutationTarget.call(
        turn: turn,
        conversation: locked_conversation,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      )
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:base], "must not rewrite output while close is in progress"
  end

  test "rejects timeline mutation after the turn has been interrupted" do
    turn = build_completed_turn_with_output!
    turn.update!(
      cancellation_reason_kind: "turn_interrupted",
      cancellation_requested_at: Time.current
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateTimelineMutationTarget.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      )
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:base], "must not rewrite output after turn interruption"
  end

  private

  def build_completed_turn_with_output!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Rewrite me",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Original output")
    turn.update!(lifecycle_state: "completed")
    turn.reload
  end
end
