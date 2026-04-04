require "test_helper"

class Conversations::RequestTurnInterruptTest < ActiveSupport::TestCase
  test "creates a close fence and requests close for mainline runtime resources while leaving detached background services open" do
    context = build_agent_control_context!
    blocking_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    optional_request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: false,
      request_payload: { "instructions" => "Optional follow up" }
    )
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    background_service = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: background_service,
      holder_key: context[:execution_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    turn_scoped_session = create_turn_scoped_subagent_session!(
      context: context,
      origin_turn: context[:turn]
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 12:00:00 UTC"))

    assert_equal "turn_interrupted", context[:turn].reload.cancellation_reason_kind
    assert_equal "turn_interrupted", context[:workflow_run].reload.cancellation_reason_kind
    assert context[:turn].active?
    assert context[:workflow_run].active?

    assert blocking_request.reload.canceled?
    assert_equal "turn_interrupted", blocking_request.result_payload["reason"]
    assert optional_request.reload.open?

    assert_equal "requested", agent_task_run.reload.close_state
    assert_equal "requested", turn_scoped_session.reload.close_state
    assert_equal "open", background_service.reload.close_state

    close_requests = AgentControlMailboxItem.where(item_type: "resource_close_request").order(:created_at)
    assert_equal 2, close_requests.count
    assert_equal [agent_task_run.public_id, turn_scoped_session.public_id].sort,
      close_requests.pluck(Arel.sql("payload ->> 'resource_id'")).sort
    assert_equal ["turn_interrupt"], close_requests.reorder(nil).distinct.pluck(Arel.sql("payload ->> 'request_kind'"))
  end

  test "interrupts in-flight subagent_step work requested by the owner turn while leaving reusable sessions open" do
    context = build_agent_control_context!
    child_session = create_reusable_subagent_session_with_running_work!(
      context: context,
      origin_turn: context[:turn]
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-28 08:30:00 UTC"))

    assert_equal "requested", child_session.fetch(:agent_task_run).reload.close_state
    assert_equal "open", child_session.fetch(:session).reload.close_state

    close_requests = AgentControlMailboxItem.where(item_type: "resource_close_request").order(:created_at)
    requested_resources = close_requests.map { |item| [item.payload.fetch("resource_type"), item.payload.fetch("resource_id")] }

    assert_includes requested_resources, ["AgentTaskRun", child_session.fetch(:agent_task_run).public_id]
    refute_includes requested_resources, ["SubagentSession", child_session.fetch(:session).public_id]
  end

  test "uses the shared close deadline schedule for turn interrupt close requests" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    travel_to Time.zone.parse("2026-03-27 11:00:00 UTC") do
      occurred_at = Time.zone.parse("2026-03-27 11:05:00 UTC")

      Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: occurred_at)
    end

    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      agent_task_run: agent_task_run
    )

    assert_equal Time.zone.parse("2026-03-27 11:05:30 UTC"), agent_task_run.reload.close_grace_deadline_at
    assert_equal Time.zone.parse("2026-03-27 11:06:00 UTC"), agent_task_run.close_force_deadline_at
    assert_equal Time.zone.parse("2026-03-27 11:05:30 UTC"), Time.zone.parse(close_request.payload.fetch("grace_deadline_at"))
    assert_equal Time.zone.parse("2026-03-27 11:06:00 UTC"), Time.zone.parse(close_request.payload.fetch("force_deadline_at"))
  end

  test "cancels queued step retry work when the turn is fenced" do
    context = build_agent_control_context!
    failed_task = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "failed",
      logical_work_id: "retry-me",
      attempt_no: 1,
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago,
      task_payload: { "step" => "tool_call" },
      terminal_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "failure_kind" => "tool_failure",
      }
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "retryable_failure",
      wait_reason_payload: {
        "retryable" => true,
        "retry_scope" => "step",
        "logical_work_id" => failed_task.logical_work_id,
        "attempt_no" => failed_task.attempt_no,
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentTaskRun",
      blocking_resource_id: failed_task.public_id
    )
    queued_retry = Workflows::StepRetry.call(workflow_run: context[:workflow_run])

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-26 12:05:00 UTC"))

    assert queued_retry.reload.canceled?
    assert_not_nil queued_retry.finished_at
    assert_equal "turn_interrupted", queued_retry.terminal_payload["cancellation_reason_kind"]

    retry_mailbox_item = AgentControlMailboxItem.find_by!(agent_task_run: queued_retry)
    assert_equal "canceled", retry_mailbox_item.status
  end

  test "cancels leased execution assignments so they are not redelivered after interrupt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_equal [mailbox_item.id], deliveries.map(&:id)
    assert_equal "leased", mailbox_item.reload.status

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-27 12:10:00 UTC"))

    assert agent_task_run.reload.canceled?
    assert_equal "canceled", mailbox_item.reload.status
    assert_nil mailbox_item.leased_to_agent_session
    assert_empty AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
  end

  test "requests turn-scoped session close even when the running session has no lease" do
    context = build_agent_control_context!
    turn_scoped_session = create_turn_scoped_subagent_session!(
      context: context,
      origin_turn: context[:turn]
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-27 10:00:00 UTC"))

    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      target_agent_program: context[:agent_program]
    )

    assert_equal "requested", turn_scoped_session.reload.close_state
    assert_equal turn_scoped_session.public_id, close_request.payload.fetch("resource_id")
    assert_equal "SubagentSession", close_request.payload.fetch("resource_type")
    assert_equal "program", close_request.runtime_plane
    refute_respond_to close_request, :target_kind
    refute_respond_to close_request, :target_ref
  end

  test "reconciles an unfinished archive close after local mainline blockers are canceled" do
    context = build_agent_control_context!
    close_operation = ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "quiescing",
      requested_at: Time.zone.parse("2026-03-27 10:15:00 UTC"),
      summary_payload: {}
    )

    Conversations::RequestTurnInterrupt.call(turn: context[:turn], occurred_at: Time.zone.parse("2026-03-27 10:16:00 UTC"))

    assert context[:conversation].reload.archived?
    assert_equal "completed", close_operation.reload.lifecycle_state
    assert_not_nil close_operation.completed_at
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_turn_count")
    assert_equal 0, close_operation.summary_payload.dig("mainline", "active_workflow_count")
  end

  test "reloads a cached-nil workflow association before fencing interrupt state" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Interrupt me",
      execution_runtime: context[:execution_runtime],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert_nil turn.workflow_run

    workflow_run = create_workflow_run!(turn: Turn.find(turn.id))

    Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: Time.zone.parse("2026-03-29 10:00:00 UTC"))

    assert_equal "turn_interrupted", turn.reload.cancellation_reason_kind
    assert_equal "turn_interrupted", workflow_run.reload.cancellation_reason_kind
  end

  private

  def create_turn_scoped_subagent_session!(context:, origin_turn:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:deployment],
      addressability: "agent_addressable"
    )

    SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      origin_turn: origin_turn,
      scope: "turn",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
  end

  def create_reusable_subagent_session_with_running_work!(context:, origin_turn:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:deployment],
      addressability: "agent_addressable"
    )
    session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    child_turn = Turns::StartAgentTurn.call(
      conversation: child_conversation,
      content: "Reusable delegated work",
      sender_kind: "owner_agent",
      sender_conversation: context[:conversation],
      agent_program_version: context[:deployment],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    child_workflow_run = create_workflow_run!(turn: child_turn)
    child_workflow_node = create_workflow_node!(workflow_run: child_workflow_run)
    child_task_run = create_agent_task_run!(
      workflow_node: child_workflow_node,
      conversation: child_conversation,
      turn: child_turn,
      kind: "subagent_step",
      lifecycle_state: "running",
      started_at: Time.current,
      subagent_session: session,
      origin_turn: origin_turn
    )
    Leases::Acquire.call(
      leased_resource: child_task_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    {
      conversation: child_conversation,
      session: session,
      turn: child_turn,
      workflow_run: child_workflow_run,
      workflow_node: child_workflow_node,
      agent_task_run: child_task_run,
    }
  end
end
