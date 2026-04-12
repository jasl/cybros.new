require "test_helper"

class Conversations::RollbackToTurnTest < ActiveSupport::TestCase
  test "rejects rollback when the conversation is pending delete" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(first_turn, content: "First output")
    first_turn.update!(lifecycle_state: "completed")
    conversation.update!(deletion_state: "pending_delete", deleted_at: Time.current)

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RollbackToTurn.call(conversation: conversation, turn: first_turn)
    end

    assert_includes error.record.errors[:deletion_state], "must be retained before rolling back the conversation"
  end

  test "cancels later turns so the target turn becomes the active tail" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_turn.update!(lifecycle_state: "completed")
    attach_selected_output!(first_turn, content: "First output")

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(second_turn, content: "Second output")
    second_turn.update!(lifecycle_state: "completed")

    restored = Conversations::RollbackToTurn.call(
      conversation: conversation,
      turn: first_turn
    )

    assert_equal first_turn, restored
    assert second_turn.reload.canceled?
    assert restored.reload.tail_in_active_timeline?
  end

  test "preserves retained summary context while dropping superseded post rollback support state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    third_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Third input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn.update!(lifecycle_state: "completed")
    third_turn.update!(lifecycle_state: "completed")
    first_message = first_turn.selected_input_message
    second_message = second_turn.selected_input_message
    third_message = third_turn.selected_input_message
    retained_segment = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: first_message,
      end_message: second_message,
      content: "Retained summary"
    )
    retained_import = Conversations::AddImport.call(
      conversation: conversation,
      kind: "quoted_context",
      summary_segment: retained_segment
    )
    superseding_segment = ConversationSummaries::CreateSegment.call(
      conversation: conversation,
      start_message: first_message,
      end_message: third_message,
      content: "Superseding summary",
      supersedes: retained_segment
    )
    superseded_import = Conversations::AddImport.call(
      conversation: conversation,
      kind: "merge_summary",
      summary_segment: superseding_segment
    )

    Conversations::RollbackToTurn.call(conversation: conversation, turn: second_turn)

    assert third_turn.reload.canceled?
    assert_equal [retained_segment.id], ConversationSummarySegment.where(conversation: conversation).pluck(:id)
    assert_nil retained_segment.reload.superseded_by
    assert_equal [retained_import.id], ConversationImport.where(conversation: conversation).pluck(:id)
    assert_not ConversationImport.exists?(superseded_import.id)
  end

  test "rejects rollback after the target turn has been interrupted" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_turn.update!(
      lifecycle_state: "canceled",
      cancellation_reason_kind: "turn_interrupted",
      cancellation_requested_at: Time.current
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RollbackToTurn.call(conversation: conversation, turn: first_turn)
    end

    assert_includes error.record.errors[:base], "must not roll back the timeline after turn interruption"
    assert second_turn.reload.active?
  end

  test "rejects rollback while later turns still own live runtime state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(first_turn, content: "First output")
    first_turn.update!(lifecycle_state: "completed")

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Second input",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(second_turn, content: "Second output")
    second_turn.update!(lifecycle_state: "completed")
    workflow_run = create_workflow_run!(turn: second_turn, lifecycle_state: "active")

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RollbackToTurn.call(conversation: conversation, turn: first_turn)
    end

    assert_includes error.record.errors[:base], "must not roll back the timeline while later workflow runs remain active"
    assert second_turn.reload.completed?
    assert workflow_run.reload.active?
    assert_equal [1, 2], conversation.turns.order(:sequence).pluck(:sequence)
  end
end
