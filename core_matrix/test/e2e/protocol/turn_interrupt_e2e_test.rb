require "test_helper"

class TurnInterruptE2ETest < ActionDispatch::IntegrationTest
  test "execution terminal reports only mutate the lifecycle path for the accepted holder agent_snapshot" do
    context = build_agent_control_context!
    holder_harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      agent_snapshot: context[:agent_snapshot],
      agent_connection_credential: context[:agent_connection_credential]
    )
    sibling_agent = create_agent!(installation: context[:installation])
    sibling_execution_runtime = create_execution_runtime!(installation: context[:installation])
    sibling_registration = register_agent_runtime!(
      installation: context[:installation],
      actor: context[:actor],
      agent: sibling_agent,
      execution_runtime: sibling_execution_runtime,
      reuse_enrollment: true
    )
    sibling_registration.fetch(:agent_connection).update!(
      health_status: "healthy",
      last_heartbeat_at: Time.current,
      last_health_check_at: Time.current
    )
    sibling_harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      agent_snapshot: sibling_registration.fetch(:agent_snapshot),
      agent_connection_credential: sibling_registration.fetch(:agent_connection_credential)
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    holder_harness.poll!
    holder_harness.report!(
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    sibling_terminal = sibling_harness.report!(
      method_id: "execution_complete",
      protocol_message_id: "sibling-terminal-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "wrong agent_snapshot" }
    )

    assert_equal 409, sibling_terminal.fetch("http_status")
    assert_equal "stale", sibling_terminal.fetch("result")
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:agent_snapshot], agent_task_run.holder_agent_snapshot

    holder_terminal = holder_harness.report!(
      method_id: "execution_complete",
      protocol_message_id: "holder-terminal-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "accepted agent_snapshot" }
    )

    assert_equal 200, holder_terminal.fetch("http_status")
    assert_equal "accepted", holder_terminal.fetch("result")
    assert_equal "completed", agent_task_run.reload.lifecycle_state
  end

  test "turn interrupt fences late execution reports and cancels the turn once mainline close completes" do
    context = build_agent_control_context!
    harness = FakeAgentRuntimeHarness.new(
      test_case: self,
      agent_snapshot: context[:agent_snapshot],
      agent_connection_credential: context[:agent_connection_credential]
    )
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    assignment = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    subagent_connection = create_turn_scoped_subagent_connection!(context: context)
    [agent_task_run].each do |resource|
      Leases::Acquire.call(
        leased_resource: resource,
        holder_key: context[:agent_snapshot].public_id,
        heartbeat_timeout_seconds: 30
      )
    end

    harness.poll!
    harness.report!(
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 30
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 13:00:00 UTC"))

    late_progress = harness.report!(
      method_id: "execution_progress",
      protocol_message_id: "late-progress-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      progress_payload: { "state" => "late" }
    )

    assert_equal 409, late_progress.fetch("http_status")
    assert_equal "stale", late_progress.fetch("result")

    close_requests = harness.poll!.fetch("mailbox_items")
    assert_equal 2, close_requests.size

    close_requests.each do |mailbox_item|
      report_resource_closed!(
        harness: harness,
        mailbox_item: mailbox_item,
        close_outcome_kind: "graceful"
      )
    end

    late_terminal = harness.report!(
      method_id: "execution_complete",
      protocol_message_id: "late-terminal-#{next_test_sequence}",
      mailbox_item_id: assignment.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: { "output" => "too late" }
    )

    assert_equal 409, late_terminal.fetch("http_status")
    assert_equal "stale", late_terminal.fetch("result")
    assert context[:turn].reload.canceled?
    assert context[:workflow_run].reload.canceled?
    assert_equal "closed", subagent_connection.reload.derived_close_status
    assert subagent_connection.close_closed?
  end

  private

  def create_turn_scoped_subagent_connection!(context:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot],
      addressability: "agent_addressable"
    )

    SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      origin_turn: context[:turn],
      scope: "turn",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
  end

  def report_resource_closed!(harness:, mailbox_item:, close_outcome_kind:)
    harness.report!(
      method_id: "resource_closed",
      protocol_message_id: "close-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.fetch("item_id"),
      close_request_id: mailbox_item.fetch("item_id"),
      resource_type: mailbox_item.fetch("payload").fetch("resource_type"),
      resource_id: mailbox_item.fetch("payload").fetch("resource_id"),
      close_outcome_kind: close_outcome_kind,
      close_outcome_payload: { "source" => "e2e" }
    )
  end
end
