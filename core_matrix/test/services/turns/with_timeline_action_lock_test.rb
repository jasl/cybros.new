require "test_helper"

class Turns::WithTimelineActionLockTest < ActiveSupport::TestCase
  test "yields a turn whose conversation is active and retained" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    yielded = Turns::WithTimelineActionLock.call(
      turn: turn,
      before_phrase: "editing tail input",
      action_phrase: "edit tail input"
    ) do |current_turn|
      current_turn
    end

    assert_equal turn.id, yielded.id
    assert yielded.active?
  end

  test "rejects pending delete conversations with before phrasing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithTimelineActionLock.call(
        turn: turn,
        before_phrase: "editing tail input",
        action_phrase: "edit tail input"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before editing tail input"
  end

  test "rejects archived conversations with action phrasing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    conversation.update!(lifecycle_state: "archived")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithTimelineActionLock.call(
        turn: turn,
        before_phrase: "rewriting output",
        action_phrase: "rewrite output"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:lifecycle_state], "must belong to an active conversation to rewrite output"
  end

  test "rejects close in progress conversations with action phrasing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: "archive",
      lifecycle_state: "requested",
      requested_at: Time.current,
      summary_payload: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithTimelineActionLock.call(
        turn: turn,
        before_phrase: "rewriting output",
        action_phrase: "rewrite output"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:base], "must not rewrite output while close is in progress"
  end

  test "rejects interrupted turns with action phrasing" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Original input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    turn.update!(
      lifecycle_state: "canceled",
      cancellation_reason_kind: "turn_interrupted",
      cancellation_requested_at: Time.current
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::WithTimelineActionLock.call(
        turn: turn,
        before_phrase: "rewriting output",
        action_phrase: "rewrite output"
      ) { flunk "should not yield" }
    end

    assert_includes error.record.errors[:base], "must not rewrite output after turn interruption"
  end
end
