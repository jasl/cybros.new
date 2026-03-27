require "test_helper"

class AgentControlReportTest < ActiveSupport::TestCase
  test "report dispatch maps control methods onto the correct handler families" do
    context = build_agent_control_context!

    execution_handler = AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "execution_started",
      payload: {}
    )
    close_handler = AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "resource_closed",
      payload: {}
    )
    health_handler = AgentControl::ReportDispatch.call(
      deployment: context[:deployment],
      method_id: "deployment_health_report",
      payload: {}
    )

    assert_kind_of AgentControl::HandleExecutionReport, execution_handler
    assert_kind_of AgentControl::HandleCloseReport, close_handler
    assert_kind_of AgentControl::HandleHealthReport, health_handler
  end

  test "report delegates processing to the dispatcher-provided handler" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    dispatch_calls = []
    handler_calls = []
    message_id = "report-dispatch-#{next_test_sequence}"
    fake_handler = Struct.new(:receipt_attributes, :calls) do
      def call
        calls << :called
      end
    end.new(
      {
        mailbox_item: mailbox_item,
        agent_task_run: agent_task_run,
      },
      handler_calls
    )
    dispatch_singleton = AgentControl::ReportDispatch.singleton_class
    original_dispatch = AgentControl::ReportDispatch.method(:call)
    poll_singleton = AgentControl::Poll.singleton_class
    original_poll = AgentControl::Poll.method(:call)

    dispatch_singleton.send(:define_method, :call) do |**kwargs|
      dispatch_calls << kwargs
      fake_handler
    end
    poll_singleton.send(:define_method, :call) do |**_kwargs|
      []
    end

    result = AgentControl::Report.call(
      deployment: context[:deployment],
      method_id: "execution_progress",
      message_id: message_id,
      mailbox_item_id: mailbox_item.public_id,
      agent_task_run_id: agent_task_run.public_id,
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      progress_payload: { "state" => "stubbed" }
    )

    receipt = AgentControlReportReceipt.find_by!(installation: context[:installation], message_id: message_id)

    assert_equal "accepted", result.code
    assert_equal [:called], handler_calls
    assert_equal 1, dispatch_calls.size
    assert_equal "execution_progress", dispatch_calls.first.fetch(:method_id)
    assert_equal mailbox_item.public_id, dispatch_calls.first.fetch(:payload).fetch("mailbox_item_id")
    assert_equal mailbox_item, receipt.mailbox_item
    assert_equal agent_task_run, receipt.agent_task_run
  ensure
    dispatch_singleton.send(:define_method, :call, original_dispatch) if dispatch_singleton && original_dispatch
    poll_singleton.send(:define_method, :call, original_poll) if poll_singleton && original_poll
  end

  test "report rolls back the receipt and mailbox mutations when handler processing blows up" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    message_id = "report-exception-#{next_test_sequence}"
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
        message_id: message_id,
        mailbox_item_id: mailbox_item.public_id,
        agent_task_run_id: agent_task_run.public_id,
        logical_work_id: agent_task_run.logical_work_id,
        attempt_no: agent_task_run.attempt_no,
        progress_payload: { "state" => "boom" }
      )
    end

    assert_equal "boom", error.message
    assert_nil AgentControlReportReceipt.find_by(installation: context[:installation], message_id: message_id)
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
      message_id: "agent-start-#{next_test_sequence}",
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

  test "execution freshness validation lives in a dedicated validator" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context, attempt_no: 2)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)
    AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    validator = AgentControl::ValidateExecutionReportFreshness.new(
      deployment: context[:deployment],
      method_id: "execution_progress",
      payload: {
        "logical_work_id" => agent_task_run.logical_work_id,
        "attempt_no" => 1,
      },
      mailbox_item: mailbox_item,
      agent_task_run: agent_task_run,
      occurred_at: Time.current
    )

    assert_raises(AgentControl::Report::StaleReportError) { validator.call }
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
      message_id: "agent-progress-#{next_test_sequence}",
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
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )
    mailbox_item = MailboxScenarioBuilder.new(self).close_request!(
      context: context,
      resource: subagent_run
    ).fetch(:mailbox_item)

    assert_equal "agent_installation", mailbox_item.target_kind

    AgentControl::Poll.call(deployment: context[:replacement_deployment], limit: 10)

    ack_result = AgentControl::Report.call(
      deployment: context[:replacement_deployment],
      method_id: "resource_close_acknowledged",
      message_id: "close-ack-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentRun",
      resource_id: subagent_run.public_id
    )

    assert_equal "accepted", ack_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_run.reload.close_state

    validator = AgentControl::ValidateCloseReportFreshness.new(
      deployment: context[:previous_deployment],
      payload: {
        "close_request_id" => mailbox_item.public_id,
      },
      mailbox_item: mailbox_item,
      resource: subagent_run,
      occurred_at: Time.current
    )

    assert_raises(AgentControl::Report::StaleReportError) { validator.call }

    terminal_result = AgentControl::Report.call(
      deployment: context[:previous_deployment],
      method_id: "resource_closed",
      message_id: "close-terminal-#{next_test_sequence}",
      mailbox_item_id: mailbox_item.public_id,
      close_request_id: mailbox_item.public_id,
      resource_type: "SubagentRun",
      resource_id: subagent_run.public_id,
      close_outcome_kind: "graceful",
      close_outcome_payload: {}
    )

    assert_equal "stale", terminal_result.code
    assert_equal "acked", mailbox_item.reload.status
    assert_equal "acknowledged", subagent_run.reload.close_state
    assert subagent_run.reload.running?
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
      message_id: "close-terminal-#{next_test_sequence}",
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
end
