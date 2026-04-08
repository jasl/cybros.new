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
      executor_program: context[:executor_program],
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
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
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
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
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
      executor_program: context[:executor_program],
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

  test "delete reconcile stays disposing while dependency blockers remain after deletion finalization" do
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    anchor_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Parent fork anchor",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    parent_fork = Conversations::CreateFork.call(
      parent: root,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )
    Conversations::CreateFork.call(
      parent: parent_fork,
      historical_anchor_message_id: anchor_turn.selected_input_message_id
    )
    parent_fork.update!(deletion_state: "deleted", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: parent_fork,
      intent_kind: "delete"
    )

    Conversations::ReconcileCloseOperation.call(conversation: parent_fork)

    assert_equal "disposing", close_operation.reload.lifecycle_state
    assert_nil close_operation.completed_at
    assert_equal 1, close_operation.summary_payload.dig("dependencies", "descendant_lineage_blockers")
    assert_equal false, close_operation.summary_payload.dig("dependencies", "root_lineage_store_blocker")
  end

  test "delete reconcile moves to degraded after deletion finalization when close failures remain" do
    context = build_fork_close_context!
    create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
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

  test "delete reconcile times out expired background close requests before summarizing the tail" do
    context = build_fork_close_context!
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil,
      started_at: close_requested_at
    )
    close_request = travel_to(close_requested_at) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: background_service,
        request_kind: "deletion_force_quiesce",
        reason_kind: "conversation_deleted",
        strictness: "graceful",
        grace_deadline_at: close_requested_at + 30.seconds,
        force_deadline_at: close_requested_at + 60.seconds
      )
    end
    clear_mainline!(context)
    context[:conversation].update!(deletion_state: "deleted", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: context[:conversation],
      intent_kind: "delete"
    )

    Conversations::ReconcileCloseOperation.call(
      conversation: context[:conversation],
      occurred_at: close_requested_at + 61.seconds
    )

    assert_equal "completed", close_request.reload.status
    assert background_service.reload.close_failed?
    assert background_service.lost?
    assert_equal "timed_out_forced", background_service.close_outcome_kind
    assert_equal "degraded", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal 1, close_operation.summary_payload.dig("tail", "degraded_close_count")
  end

  test "delete reconcile completes after deletion finalization when no tail blockers remain" do
    context = build_fork_close_context!
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

  test "reconcile uses blocker snapshot predicates instead of re-encoding summary hashes" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    conversation.update!(deletion_state: "deleted", deleted_at: close_requested_at)
    close_operation = create_close_operation!(
      conversation: conversation,
      intent_kind: "delete"
    )
    fake_snapshot = Struct.new(:close_summary) do
      def mainline_clear?
        true
      end

      def tail_pending?
        true
      end

      def tail_degraded?
        false
      end

      def dependency_blocked?
        false
      end
    end.new(
      {
        mainline: {
          active_turn_count: 0,
          active_workflow_count: 0,
          active_agent_task_count: 0,
          open_blocking_interaction_count: 0,
          running_subagent_count: 0,
        },
        tail: {
          running_background_process_count: 0,
          detached_tool_process_count: 0,
          degraded_close_count: 0,
        },
        dependencies: {
          descendant_lineage_blockers: 0,
          root_lineage_store_blocker: false,
          variable_provenance_blocker: false,
          import_provenance_blocker: false,
        },
      }
    )

    original_call = Conversations::BlockerSnapshotQuery.method(:call)
    Conversations::BlockerSnapshotQuery.singleton_class.define_method(:call) do |*args, **kwargs|
      fake_snapshot
    end

    begin
      Conversations::ReconcileCloseOperation.call(conversation: conversation)
    ensure
      Conversations::BlockerSnapshotQuery.singleton_class.define_method(:call, original_call)
    end

    assert_equal "disposing", close_operation.reload.lifecycle_state
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

  def build_fork_close_context!
    context = create_workspace_context!
    root = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      executor_program: context[:executor_program],
      agent_program_version: context[:agent_program_version]
    )
    root_turn = Turns::StartUserTurn.call(
      conversation: root,
      content: "Fork close anchor",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    conversation = Conversations::CreateFork.call(
      parent: root,
      historical_anchor_message_id: root_turn.selected_input_message_id
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Fork close work",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: turn)
    workflow_node = create_workflow_node!(workflow_run: workflow_run)

    context.merge(
      conversation: conversation,
      turn: turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node
    )
  end

  def close_requested_at
    @close_requested_at ||= Time.zone.parse("2026-03-27 09:00:00 UTC")
  end
end
