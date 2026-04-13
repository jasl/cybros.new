require "test_helper"

class ConversationExecutionContinuityConstraintTest < NonTransactionalConcurrencyTestCase
  test "database constraint rejects ready continuity without a current epoch" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])

    error = assert_raises(ActiveRecord::StatementInvalid) do
      conversation.update_column(:execution_continuity_state, "ready")
    end

    assert_includes error.message, "chk_conversations_execution_continuity_state"
    assert_equal "not_started", conversation.reload.execution_continuity_state
    assert_nil conversation.current_execution_epoch
  end

  test "database constraint rejects not_started continuity once a current epoch exists" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    initialize_current_execution_epoch!(conversation)

    error = assert_raises(ActiveRecord::StatementInvalid) do
      conversation.update_column(:execution_continuity_state, "not_started")
    end

    assert_includes error.message, "chk_conversations_execution_continuity_state"
    assert_equal "ready", conversation.reload.execution_continuity_state
    assert conversation.current_execution_epoch.present?
  end
end
