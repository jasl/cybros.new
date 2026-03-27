require "test_helper"

class Messages::UpdateVisibilityTest < ActiveSupport::TestCase
  test "creates and updates overlays without deleting immutable message rows" do
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
    message = turn.selected_input_message

    overlay = Messages::UpdateVisibility.call(
      conversation: conversation,
      message: message,
      excluded_from_context: true
    )

    assert overlay.persisted?
    assert_not overlay.hidden?
    assert overlay.excluded_from_context?
    assert_equal [message.id], Conversations::TranscriptProjection.call(conversation: conversation).map(&:id)
    assert_empty Conversations::ContextProjection.call(conversation: conversation).messages

    updated = Messages::UpdateVisibility.call(
      conversation: conversation,
      message: message,
      hidden: true
    )

    assert_equal overlay.id, updated.id
    assert updated.hidden?
    assert updated.excluded_from_context?
    assert_equal "Original input", message.reload.content
  end

  test "rejects messages outside the conversation transcript projection" do
    context = create_workspace_context!
    first_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    second_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: second_conversation,
      content: "Unrelated input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: first_conversation,
        message: turn.selected_input_message,
        hidden: true
      )
    end

    assert_includes error.record.errors[:message], "must be present in the conversation transcript projection"
  end

  test "rejects hiding or excluding fork-point anchors in descendant projections" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchored input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    message = turn.selected_input_message
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: message.id
    )
    checkpoint = Conversations::CreateCheckpoint.call(
      parent: branch,
      historical_anchor_message_id: message.id
    )

    branch_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: branch,
        message: message,
        excluded_from_context: true
      )
    end

    checkpoint_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: checkpoint,
        message: message,
        hidden: true
      )
    end

    assert_includes branch_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
    assert_includes checkpoint_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
    assert_empty branch.conversation_message_visibilities
    assert_empty checkpoint.conversation_message_visibilities
  end

  test "rejects hiding or excluding source inputs required by output anchored descendants" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Anchored input",
      agent_deployment: context[:agent_deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output = attach_selected_output!(turn, content: "Anchored output")
    branch = Conversations::CreateBranch.call(
      parent: root,
      historical_anchor_message_id: output.id
    )

    hidden_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: root,
        message: turn.selected_input_message,
        hidden: true
      )
    end

    excluded_error = assert_raises(ActiveRecord::RecordInvalid) do
      Messages::UpdateVisibility.call(
        conversation: branch,
        message: turn.selected_input_message,
        excluded_from_context: true
      )
    end

    assert_includes hidden_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
    assert_includes excluded_error.record.errors[:base], "fork-point messages cannot be hidden or excluded from context"
  end

  test "rejects visibility updates for archived conversations" do
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
      Messages::UpdateVisibility.call(
        conversation: conversation,
        message: turn.selected_input_message,
        hidden: true
      )
    end

    assert_includes error.record.errors[:lifecycle_state], "must be active before updating message visibility"
  end
end
