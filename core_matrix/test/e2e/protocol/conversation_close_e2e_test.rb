require "test_helper"

class ConversationCloseE2ETest < ActionDispatch::IntegrationTest
  test "archive force reaches archived with degraded tail residue after mainline close succeeds" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    turn_command = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )
    [agent_task_run, turn_command, background_service, subagent_run].each do |resource|
      Leases::Acquire.call(
        leased_resource: resource,
        holder_key: context[:deployment].public_id,
        heartbeat_timeout_seconds: 30
      )
    end

    harness.poll!
    harness.report!(
      method_id: "execution_started",
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    archived = Conversations::Archive.call(
      conversation: context[:conversation],
      force: true,
      occurred_at: Time.zone.parse("2026-03-26 14:00:00 UTC")
    )

    assert archived.active?

    close_requests = harness.poll!.fetch("mailbox_items").index_by { |item| item.fetch("payload").fetch("resource_id") }
    report_resource_closed!(
      harness: harness,
      mailbox_item: close_requests.fetch(agent_task_run.public_id),
      close_outcome_kind: "graceful"
    )
    report_resource_closed!(
      harness: harness,
      mailbox_item: close_requests.fetch(turn_command.public_id),
      close_outcome_kind: "graceful"
    )
    report_resource_closed!(
      harness: harness,
      mailbox_item: close_requests.fetch(subagent_run.public_id),
      close_outcome_kind: "graceful"
    )
    report_resource_closed!(
      harness: harness,
      mailbox_item: close_requests.fetch(background_service.public_id),
      close_outcome_kind: "residual_abandoned"
    )

    close_operation = context[:conversation].reload.conversation_close_operations.order(:created_at).last

    assert context[:conversation].reload.archived?
    assert_equal "degraded", close_operation.lifecycle_state
    assert_equal "residual_abandoned", background_service.reload.close_outcome_kind
    assert background_service.reload.lost?
  end

  test "delete enters pending_delete immediately, finalizes after mainline close, and keeps retained children" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      deployment: context[:deployment],
      machine_credential: context[:machine_credential]
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    [agent_task_run, background_service].each do |resource|
      Leases::Acquire.call(
        leased_resource: resource,
        holder_key: context[:deployment].public_id,
        heartbeat_timeout_seconds: 30
      )
    end
    child = Conversations::CreateThread.call(parent: context[:conversation])
    child_turn = Turns::StartUserTurn.call(
      conversation: child,
      content: "Child keeps running",
      agent_deployment: context[:deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    harness.poll!
    harness.report!(
      method_id: "execution_started",
      message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    deleted = Conversations::RequestDeletion.call(
      conversation: context[:conversation],
      occurred_at: Time.zone.parse("2026-03-26 14:30:00 UTC")
    )

    assert deleted.pending_delete?

    close_requests = harness.poll!.fetch("mailbox_items").index_by { |item| item.fetch("payload").fetch("resource_id") }
    report_resource_closed!(
      harness: harness,
      mailbox_item: close_requests.fetch(agent_task_run.public_id),
      close_outcome_kind: "graceful"
    )
    report_resource_closed!(
      harness: harness,
      mailbox_item: close_requests.fetch(background_service.public_id),
      close_outcome_kind: "residual_abandoned"
    )

    finalized = Conversations::FinalizeDeletion.call(conversation: context[:conversation].reload)

    assert finalized.deleted?
    assert child.reload.retained?
    assert child_turn.reload.active?
    assert_no_difference("Conversation.count") do
      Conversations::PurgeDeleted.call(conversation: finalized.reload)
    end
  end

  private

  def report_resource_closed!(harness:, mailbox_item:, close_outcome_kind:)
    harness.report!(
      method_id: "resource_closed",
      message_id: "close-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.fetch("item_id"),
      close_request_id: mailbox_item.fetch("item_id"),
      resource_type: mailbox_item.fetch("payload").fetch("resource_type"),
      resource_id: mailbox_item.fetch("payload").fetch("resource_id"),
      close_outcome_kind: close_outcome_kind,
      close_outcome_payload: { "source" => "e2e" }
    )
  end
end
