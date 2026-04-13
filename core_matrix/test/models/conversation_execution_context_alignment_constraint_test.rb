require "test_helper"

class ConversationExecutionContextAlignmentConstraintTest < NonTransactionalConcurrencyTestCase
  test "database constraint rejects a current execution runtime that does not match the current epoch runtime" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    epoch = initialize_current_execution_epoch!(conversation)
    other_runtime = create_execution_runtime!(installation: context[:installation])

    error = assert_raises(ActiveRecord::StatementInvalid) do
      conversation.update_column(:current_execution_runtime_id, other_runtime.id)
    end

    assert_includes error.message, "fk_conversations_current_execution_context_alignment"
    assert_equal epoch.execution_runtime_id, conversation.reload.current_execution_runtime_id
  end
end
