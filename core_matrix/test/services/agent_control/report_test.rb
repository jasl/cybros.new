require "test_helper"

class AgentControlReportTest < ActiveSupport::TestCase
  test "report rolls back the receipt and mailbox mutations when handler processing blows up" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    protocol_message_id = "report-exception-#{next_test_sequence}"
    dispatch_singleton = AgentControl::ReportDispatch.singleton_class
    original_dispatch = AgentControl::ReportDispatch.method(:call)
    fake_handler = Struct.new(:receipt_attributes, :mailbox_item) do
      def call
        mailbox_item.update!(status: "acked", acked_at: Time.current)
        raise "boom"
      end
    end.new(
      {
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
      },
      mailbox_item
    )

    dispatch_singleton.send(:define_method, :call) do |**_kwargs|
      fake_handler
    end

    error = assert_raises(RuntimeError) do
      AgentControl::Report.call(
        deployment: context[:deployment],
        method_id: "execution_progress",
        protocol_message_id: protocol_message_id,
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: { "state" => "boom" }
      )
    end

    assert_equal "boom", error.message
    assert_nil AgentControlReportReceipt.find_by(installation: context[:installation], protocol_message_id: protocol_message_id)
    assert_equal "queued", mailbox_item.reload.status
    assert_nil mailbox_item.acked_at
  ensure
    dispatch_singleton.send(:define_method, :call, original_dispatch) if dispatch_singleton && original_dispatch
  end

  test "execution_started acknowledges the offered delivery and acquires the task lease" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    assert_equal "accepted", result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "running", agent_task_run.reload.lifecycle_state
    assert_equal context[:deployment], agent_task_run.holder_agent_deployment
    assert_equal context[:deployment].public_id, agent_task_run.execution_lease.holder_key
  end

  test "execution reports materialize a succeeded agent-owned tool invocation from progress and terminal payloads" do
    context = build_calculator_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    call_id = "tool-call-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      protocol_message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      progress_payload: {
        "state" => "tool_reviewed",
        "tool_invocation" => {
          "event" => "started",
          "call_id" => call_id,
          "tool_name" => "calculator",
          "request_payload" => {
            "tool_name" => "calculator",
            "arguments" => { "expression" => "2 + 2" },
          },
        },
      }
    )

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_complete",
      protocol_message_id: "agent-complete-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: {
        "output" => "The calculator returned 4.",
        "tool_invocations" => [
          {
            "event" => "completed",
            "call_id" => call_id,
            "tool_name" => "calculator",
            "response_payload" => { "content" => "The calculator returned 4." },
          },
        ],
      }
    )

    invocation = agent_task_run.reload.tool_invocations.sole

    assert_equal "succeeded", invocation.status
    assert_equal "calculator", invocation.tool_definition.tool_name
    assert_equal call_id, invocation.idempotency_key
    assert_equal "2 + 2", invocation.request_payload.dig("arguments", "expression")
    assert_equal "The calculator returned 4.", invocation.response_payload.fetch("content")
  end

  test "execution_fail materializes denied agent-owned tool invocations with explicit rejection details" do
    context = build_calculator_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      protocol_message_id: "agent-start-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      expected_duration_seconds: 15
    )

    call_id = "tool-call-#{next_test_sequence}"

    AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_fail",
      protocol_message_id: "agent-fail-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      terminal_payload: {
        "failure_kind" => "runtime_error",
        "last_error_summary" => "tool calculator is not allowed",
        "retryable" => false,
        "tool_invocations" => [
          {
            "event" => "failed",
            "call_id" => call_id,
            "tool_name" => "calculator",
            "error_payload" => {
              "classification" => "authorization",
              "code" => "tool_not_allowed",
              "message" => "tool calculator is not allowed",
              "retryable" => false,
            },
          },
        ],
      }
    )

    invocation = agent_task_run.reload.tool_invocations.sole

    assert_equal "failed", invocation.status
    assert_equal "calculator", invocation.tool_definition.tool_name
    assert_equal call_id, invocation.idempotency_key
    assert_equal "authorization", invocation.error_payload.fetch("classification")
    assert_equal "tool_not_allowed", invocation.error_payload.fetch("code")
  end

  test "rejects stale reports from a superseded attempt" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context, attempt_no: 2)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      protocol_message_id: "agent-progress-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: 1,
      progress_payload: { "state" => "late" }
    )

    assert_equal "stale", result.code
    assert_equal({}, agent_task_run.reload.progress_payload)
  end

  test "rejects terminal close reports from a sibling deployment after another deployment acknowledged the request" do
    context = build_rotated_runtime_context!
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: subagent_session
    ).fetch(:mailbox_item)

    assert_equal "agent_installation", mailbox_item.target_kind

    AgentControl::Poll.call(deployment: context[:replacement_deployment], limit: 10)

    ack_result = AgentControl::Report.call(
      deployment: context[:replacement_deployment],
      method_id: "resource_close_acknowledged",
      protocol_message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentSession",
      resource_id: subagent_session.public_id
    )

    assert_equal "accepted", ack_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_session.reload.close_state

    terminal_result = AgentControl::Report.call(
      deployment: context[:previous_deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentSession",
      resource_id: subagent_session.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    assert_equal "stale", terminal_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_session.reload.close_state
    assert_equal "close_requested", subagent_session.reload.derived_close_status
    assert subagent_session.observed_status_running?
  end

  test "resource_closed terminalizes a subagent session and updates durable status" do
    context = build_agent_control_context!
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      origin_turn: context[:turn],
      scope: "turn",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    close_request = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: subagent_session
    ).fetch(:mailbox_item)

    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "SubagentSession",
      resource_id: subagent_session.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    assert_equal "accepted", result.code
    assert_equal "completed", close_request.reload.status
    assert subagent_session.reload.close_closed?
    assert_equal "closed", subagent_session.derived_close_status
    assert subagent_session.observed_status_interrupted?
  end

  test "forced requeue keeps the last acknowledged deployment valid until a new lease takes over" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-28 12:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      ).fetch(:mailbox_item)
    end

    AgentControl::Poll.call(deployment: context[:deployment], limit: 10, occurred_at: occurred_at)

    ack_result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "resource_close_acknowledged",
      protocol_message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      occurred_at: occurred_at
    )

    assert_equal "accepted", ack_result.code
    assert_equal "acked", close_request.reload.status
    assert_equal context[:deployment], close_request.leased_to_agent_deployment

    AgentControl::ProgressCloseRequest.call(
      mailbox_item: close_request,
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal "queued", close_request.reload.status
    assert_equal "forced", close_request.payload["strictness"]
    assert_equal context[:deployment], close_request.leased_to_agent_deployment

    terminal_result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {},
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal "accepted", terminal_result.code
    assert_equal "completed", close_request.reload.status
    assert process_run.reload.close_closed?
    assert process_run.stopped?
  end

  test "late terminal close reports stay stale after kernel timeout terminalizes the close request" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-28 13:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = travel_to(occurred_at) do
      MailboxScenarioBuilder.new(self).close_request!(
        context: context,
        resource: process_run
      ).fetch(:mailbox_item)
    end

    AgentControl::Poll.call(deployment: context[:deployment], limit: 10, occurred_at: occurred_at)

    ack_result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "resource_close_acknowledged",
      protocol_message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      occurred_at: occurred_at
    )

    assert_equal "accepted", ack_result.code

    AgentControl::ProgressCloseRequest.call(
      mailbox_item: close_request,
      occurred_at: occurred_at + 61.seconds
    )

    process_run.reload
    close_request.reload

    assert process_run.close_failed?
    assert process_run.lost?
    assert_equal "completed", close_request.status
    assert_equal "timed_out_forced", process_run.close_outcome_kind

    terminal_result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: close_request.public_id,
      close_request_id: close_request.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {},
      occurred_at: occurred_at + 61.seconds
    )

    assert_equal "stale", terminal_result.code
    assert process_run.reload.close_failed?
    assert_equal "timed_out_forced", process_run.close_outcome_kind
  end

  test "duplicate resource close terminal reports do not re-enter close reconciliation" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: process_run
    ).fetch(:mailbox_item)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)
    close_operation = ConversationCloseOperation.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      intent_kind: "archive",
      lifecycle_state: "quiescing",
      requested_at: Time.current,
      summary_payload: {}
    )
    calls = []
    singleton = Conversations::ReconcileCloseOperation.singleton_class
    original_call = Conversations::ReconcileCloseOperation.method(:call)

    singleton.send(:define_method, :call) do |*args, **kwargs, &block|
      calls << [args, kwargs]
      original_call.call(*args, **kwargs, &block)
    end

    params = {
      deployment: context[:deployment],
      method_id: "resource_closed",
      protocol_message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "ProcessRun",
      resource_id: process_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {},
    }

    first_result = AgentControl::Report.call(**params)
    duplicate_result = AgentControl::Report.call(**params)

    assert_equal "accepted", first_result.code
    assert_equal "duplicate", duplicate_result.code
    assert_equal 1, calls.size
    assert_equal close_operation.reload.id, context[:conversation].reload.conversation_close_operations.order(:created_at).last.id
  ensure
    singleton.send(:define_method, :call, original_call) if singleton && original_call
  end

  private

  def build_calculator_agent_control_context!
    context = build_agent_control_context!
    capability_snapshot = create_capability_snapshot!(
      agent_deployment: context[:deployment],
      version: 2,
      tool_catalog: [
        {
          "tool_name" => "calculator",
          "tool_kind" => "agent_observation",
          "implementation_source" => "agent",
          "implementation_ref" => "agent/calculator",
          "input_schema" => { "type" => "object", "properties" => {} },
          "result_schema" => { "type" => "object", "properties" => {} },
          "streaming_support" => false,
          "idempotency_policy" => "best_effort",
        },
      ],
      profile_catalog: {
        "main" => {
          "label" => "Main",
          "description" => "Primary interactive profile",
          "allowed_tool_names" => ["calculator"],
        },
      },
      config_schema_snapshot: default_config_schema_snapshot(include_selector_slots: true),
      default_config_snapshot: default_default_config_snapshot(include_selector_slots: true)
    )
    context[:deployment].update!(active_capability_snapshot: capability_snapshot)
    context[:turn].update!(
      resolved_model_selection_snapshot: context[:turn].resolved_model_selection_snapshot.merge(
        "capability_snapshot_id" => capability_snapshot.id
      )
    )

    conversation = context[:conversation].reload
    turn = context[:turn].reload

    Conversations::RefreshRuntimeContract.call(conversation: conversation)
    execution_snapshot = Workflows::BuildExecutionSnapshot.call(turn: turn)
    turn.update!(execution_snapshot_payload: execution_snapshot.to_h)

    context.merge(
      conversation: conversation.reload,
      turn: turn.reload,
      workflow_run: context[:workflow_run].reload,
      workflow_node: context[:workflow_node].reload
    )
  end
end
