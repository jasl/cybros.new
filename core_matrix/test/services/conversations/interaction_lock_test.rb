require "test_helper"

class Conversations::InteractionLockTest < ActiveSupport::TestCase
  test "revoked workspace agents keep conversations readable to the owner" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )

    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "user_revoked"
    )

    assert_equal "locked_agent_access_revoked", conversation.reload.interaction_lock_state
    assert_includes Conversation.accessible_to_user(context[:user]).to_a, conversation
  end

  test "revoked workspace agents block new main transcript entry and queued follow up" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace]
    )
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Initial input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    context[:workspace_agent].update!(
      lifecycle_state: "revoked",
      revoked_at: Time.current,
      revoked_reason_kind: "user_revoked"
    )

    start_error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartUserTurn.call(
        conversation: conversation,
        content: "Blocked input",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    queue_error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::QueueFollowUp.call(
        conversation: conversation,
        content: "Blocked follow up",
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )
    end

    assert_includes start_error.record.errors[:interaction_lock_state], "must be mutable for user turn entry"
    assert_includes queue_error.record.errors[:interaction_lock_state], "must be mutable for follow up turn entry"
  end
end
