require "test_helper"

class TranscriptVisibilityAttachmentFlowTest < ActionDispatch::IntegrationTest
  test "branch and checkpoint attachment projections follow message visibility overlays" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_snapshot: context[:agent_snapshot],
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

    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: branch).map(&:id)
    assert_equal [attachment.id], Conversations::ContextProjection.call(conversation: branch).attachments.map(&:id)

    branch_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: branch,
        message: message,
        excluded_from_context: true
      )
    end

    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: branch).map(&:id)
    assert_equal [message.id], Conversations::ContextProjection.call(conversation: branch).messages.map(&:id)
    assert_equal [attachment.id], Conversations::ContextProjection.call(conversation: branch).attachments.map(&:id)
    assert_equal [attachment.id], Conversations::ContextProjection.call(conversation: root).attachments.map(&:id)
    assert_includes branch_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"

    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: message.id
    )

    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: checkpoint).map(&:id)
    assert_equal [attachment.id], Conversations::ContextProjection.call(conversation: checkpoint).attachments.map(&:id)

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

    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: root).map(&:id)
    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: branch).map(&:id)
    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: checkpoint).map(&:id)
    assert_equal [attachment.id], Conversations::ContextProjection.call(conversation: checkpoint).attachments.map(&:id)
    assert_includes checkpoint_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
  end

  test "branch descendants can checkpoint against inherited transcript anchors" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: turn.selected_input_message_id
    )

    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: turn.selected_input_message_id
    )

    assert_equal [turn.selected_input_message_id], Conversations::TranscriptProjection.call(conversation: branch).map(&:id)
    assert_equal [turn.selected_input_message_id], Conversations::TranscriptProjection.call(conversation: checkpoint).map(&:id)
  end

  test "output anchored descendants protect the source input from visibility edits" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Root input",
      agent_snapshot: context[:agent_snapshot],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Root output")
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: output.id
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: branch,
        message: turn.selected_input_message,
        hidden: true
      )
    end

    assert_equal ["Root input", "Root output"], Conversations::TranscriptProjection.call(conversation: root).map(&:content)
    assert_equal ["Root input", "Root output"], Conversations::TranscriptProjection.call(conversation: branch).map(&:content)
    assert_includes error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
  end
end
