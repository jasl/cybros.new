require "test_helper"

class TranscriptVisibilityAttachmentFlowTest < ActionDispatch::IntegrationTest
  test "branch and checkpoint attachment projections follow message visibility overlays" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message
    attachment = create_message_attachment!(
      message: message,
      filename: "brief.txt",
      body: "brief attachment"
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: message.id
    )

    assert_equal [message.id], branch.transcript_projection_messages.map(&:id)
    assert_equal [attachment.id], branch.context_projection_attachments.map(&:id)

    branch_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: branch,
        message: message,
        excluded_from_context: true
      )
    end

    assert_equal [message.id], branch.transcript_projection_messages.map(&:id)
    assert_equal [message.id], branch.context_projection_messages.map(&:id)
    assert_equal [attachment.id], branch.context_projection_attachments.map(&:id)
    assert_equal [attachment.id], root.context_projection_attachments.map(&:id)
    assert_includes branch_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"

    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: message.id
    )

    assert_equal [message.id], checkpoint.transcript_projection_messages.map(&:id)
    assert_equal [attachment.id], checkpoint.context_projection_attachments.map(&:id)

    checkpoint_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: checkpoint,
        message: message,
        hidden: true
      )
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: root,
        message: message,
        hidden: true
      )
    end

    assert_equal [message.id], root.transcript_projection_messages.map(&:id)
    assert_equal [message.id], branch.transcript_projection_messages.map(&:id)
    assert_equal [message.id], checkpoint.transcript_projection_messages.map(&:id)
    assert_equal [attachment.id], checkpoint.context_projection_attachments.map(&:id)
    assert_includes checkpoint_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
  end
end
