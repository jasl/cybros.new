require "test_helper"

class ConversationExecutionEpochs::RetargetCurrentTest < ActiveSupport::TestCase
  test "retargets the current epoch and keeps the conversation ready" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    original_epoch = initialize_current_execution_epoch!(conversation)
    alternate_runtime = create_execution_runtime!(installation: context[:installation], display_name: "Alternate Runtime")
    create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: alternate_runtime
    )

    epoch = ConversationExecutionEpochs::RetargetCurrent.call(
      conversation: conversation,
      execution_runtime: alternate_runtime
    )

    assert_equal original_epoch, epoch
    assert_equal alternate_runtime, epoch.reload.execution_runtime
    assert_equal alternate_runtime, conversation.reload.current_execution_runtime
    assert_equal "ready", conversation.execution_continuity_state
  end

  test "raises when continuity has not been initialized yet" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    alternate_runtime = create_execution_runtime!(installation: context[:installation], display_name: "Alternate Runtime")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      ConversationExecutionEpochs::RetargetCurrent.call(
        conversation: conversation,
        execution_runtime: alternate_runtime
      )
    end

    assert_includes error.record.errors[:current_execution_epoch], "must exist before retargeting execution continuity"
    assert_nil conversation.reload.current_execution_epoch
    assert_equal "not_started", conversation.execution_continuity_state
  end
end
