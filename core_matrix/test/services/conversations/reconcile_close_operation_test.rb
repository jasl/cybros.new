require "test_helper"

class Conversations::ReconcileCloseOperationTest < ActiveSupport::TestCase
  test "archive reconcile stays quiescing while mainline blockers remain" do
    context = build_agent_control_context!
    create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: close_requested_at
    )
    close_operation = create_close_operation!(
      conversation: context[:conversation],
      intent_kind: "archive"
    )

    Conversations::ReconcileCloseOperation.call(conversation: context[:conversation])

    assert_equal "quiescing", close_operation.reload.lifecycle_state
    assert context[:conversation].reload.active?
    assert_equal 1, close_operation.summary_payload.dig("mainline", "active_turn_count")
    assert_equal 1, close_operation.summary_payload.dig("mainline", "active_workflow_count")
    assert_equal 1, close_operation.summary_payload.dig("mainline", "active_agent_task_count")
    assert_nil close_operation.completed_at
  end

  test "archive reconcile archives the conversation once mainline is clear but tail is still disposing" do
    context = build_agent_control_context!
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil,
      started_at: close_requested_at
    )
    clear_mainline!(context)
    close_operation = create_close_operation!(
      conversation: context[:conversation],
      intent_kind: "archive"
    )

    Conversations::ReconcileCloseOperation.call(conversation: context[:conversation])

    assert context[:conversation].reload.archived?
    assert_equal "disposing", close_operation.reload.lifecycle_state
    assert_equal 1, close_operation.summary_payload.dig("tail", "running_background_process_count")
    assert_nil close_operation.completed_at
  end

  test "archive reconcile completes once both mainline and tail are clear" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    close_operation = create_close_operation!(
      conversation: conversation,
      intent_kind: "archive"
    )

    Conversations::ReconcileCloseOperation.call(conversation: conversation)

    assert conversation.reload.archived?
    assert_equal "completed", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_turn_count")
    assert_equal 0, close_operation.summary_payload.dig("tail", "running_background_process_count")
  end

  test "delete reconcile stays quiescing until the conversation is deleted" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment]
    )
    conversation.update!(deletion_state: "pending_delete", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: conversation,
      intent_kind: "delete"
    )

    Conversations::ReconcileCloseOperation.call(conversation: conversation)

    assert conversation.reload.pending_delete?
    assert_equal "quiescing", close_operation.reload.lifecycle_state
    assert_nil close_operation.completed_at
  end

  test "delete reconcile moves to disposing only after deletion finalization" do
    context = build_agent_control_context!
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil,
      started_at: close_requested_at
    )
    clear_mainline!(context)
    context[:conversation].update!(deletion_state: "deleted", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: context[:conversation],
      intent_kind: "delete"
    )

    Conversations::ReconcileCloseOperation.call(conversation: context[:conversation])

    assert_equal "disposing", close_operation.reload.lifecycle_state
    assert_nil close_operation.completed_at
  end

  test "delete reconcile moves to degraded after deletion finalization when close failures remain" do
    context = build_agent_control_context!
    create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      lifecycle_state: "lost",
      timeout_seconds: nil,
      started_at: close_requested_at,
      ended_at: close_requested_at + 5.seconds,
      close_state: "failed",
      close_reason_kind: "conversation_deleted",
      close_requested_at: close_requested_at,
      close_acknowledged_at: close_requested_at + 1.second,
      close_outcome_kind: "timed_out_forced",
      close_outcome_payload: {}
    )
    clear_mainline!(context)
    context[:conversation].update!(deletion_state: "deleted", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: context[:conversation],
      intent_kind: "delete"
    )

    Conversations::ReconcileCloseOperation.call(conversation: context[:conversation])

    assert_equal "degraded", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal 1, close_operation.summary_payload.dig("tail", "degraded_close_count")
  end

  test "delete reconcile completes after deletion finalization when no tail blockers remain" do
    context = build_agent_control_context!
    clear_mainline!(context)
    context[:conversation].update!(deletion_state: "deleted", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: context[:conversation],
      intent_kind: "delete"
    )

    Conversations::ReconcileCloseOperation.call(conversation: context[:conversation])

    assert_equal "completed", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert context[:conversation].reload.deleted?
  end

  private

  def create_close_operation!(conversation:, intent_kind:, lifecycle_state: "requested")
    ConversationCloseOperation.create!(
      installation: conversation.installation,
      conversation: conversation,
      intent_kind: intent_kind,
      lifecycle_state: lifecycle_state,
      requested_at: close_requested_at,
      summary_payload: {}
    )
  end

  def clear_mainline!(context)
    context[:workflow_run].update!(
      lifecycle_state: "canceled",
      wait_state: "ready",
      wait_reason_kind: nil,
      wait_reason_payload: {},
      waiting_since_at: nil,
      blocking_resource_type: nil,
      blocking_resource_id: nil,
      cancellation_requested_at: close_requested_at,
      cancellation_reason_kind: "turn_interrupted"
    )
    context[:turn].update!(
      lifecycle_state: "canceled",
      cancellation_requested_at: close_requested_at,
      cancellation_reason_kind: "turn_interrupted"
    )
  end

  def close_requested_at
    @close_requested_at ||= Time.zone.parse("2026-03-27 09:00:00 UTC")
  end
end
