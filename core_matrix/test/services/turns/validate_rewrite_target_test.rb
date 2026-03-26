require "test_helper"

class Turns::ValidateRewriteTargetTest < ActiveSupport::TestCase
  test "rejects rewrite when the conversation is pending delete" do
    turn = build_completed_turn_with_output!
    turn.conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateRewriteTarget.call(turn: turn)
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:deletion_state], "must be retained before rewriting output"
  end

  test "rejects rewrite when the conversation is archived" do
    turn = build_completed_turn_with_output!
    turn.conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateRewriteTarget.call(turn: turn)
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:lifecycle_state], "must belong to an active conversation to rewrite output"
  end

  test "rejects rewrite while close is in progress" do
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
      Turns::ValidateRewriteTarget.call(turn: turn)
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:base], "must not rewrite output while close is in progress"
  end

  test "rejects rewrite after the turn has been interrupted" do
    turn = build_completed_turn_with_output!
    turn.update!(
      cancellation_reason_kind: "turn_interrupted",
      cancellation_requested_at: Time.current
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::ValidateRewriteTarget.call(turn: turn)
    end

    assert_same turn, error.record
    assert_includes error.record.errors[:base], "must not rewrite output after turn interruption"
  end

  private

  def build_completed_turn_with_output!
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Rewrite me",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(turn, content: "Original output")
    turn.update!(lifecycle_state: "completed")
    turn.reload
  end
end
