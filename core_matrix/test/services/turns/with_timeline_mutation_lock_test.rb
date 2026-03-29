require "test_helper"

class Turns::WithTimelineMutationLockTest < ActiveSupport::TestCase
  test "legacy timeline action alias is removed" do
    refute Turns.const_defined?(:WithTimelineActionLock, false)
  end

  test "yields the turn when timeline mutation is allowed" do
    turn = build_completed_turn_with_output!

    yielded = Turns::WithTimelineMutationLock.call(
      turn: turn,
      retained_message: "must be retained before rewriting output",
      active_message: "must belong to an active conversation to rewrite output",
      closing_message: "must not rewrite output while close is in progress",
      interrupted_message: "must not rewrite output after turn interruption"
    ) do |current_turn|
      current_turn
    end

    assert_equal turn.id, yielded.id
  end

  test "rejects interrupted turns with the supplied message" do
    turn = build_completed_turn_with_output!
    turn.update!(
      lifecycle_state: "canceled",
      cancellation_reason_kind: "turn_interrupted",
      cancellation_requested_at: Time.current
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithTimelineMutationLock.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      ) { flunk "should not yield" }
    end

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
