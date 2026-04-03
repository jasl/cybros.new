require "test_helper"

class AgentControlPollTest < ActiveSupport::TestCase
  test "leases queued execution assignments and redelivers them after lease expiry" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_equal [scenario.fetch(:mailbox_item).id], deliveries.map(&:id)
    assert_equal "leased", scenario.fetch(:mailbox_item).reload.status
    assert_equal 1, scenario.fetch(:mailbox_item).delivery_no

    travel 31.seconds do
      redeliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

      assert_equal [scenario.fetch(:mailbox_item).id], redeliveries.map(&:id)
      assert_equal 2, scenario.fetch(:mailbox_item).reload.delivery_no
    end
  end

  test "program poll only delivers program-plane execution work" do
    context = build_agent_control_context!
    scenario_builder = MailboxScenarioBuilder.new(self)
    assignment = scenario_builder.execution_assignment!(context: context).fetch(:mailbox_item)
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:execution_session].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = scenario_builder.close_request!(context: context, resource: process_run).fetch(:mailbox_item)

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_equal [assignment.id], deliveries.map(&:id)
    assert_nil close_request.reload.leased_to_agent_session
    assert_nil close_request.leased_to_execution_session
  end

  test "does not lease execution-plane work on the program poll path even when program hints do not match" do
    context = build_agent_control_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      runtime_plane: "execution",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_empty deliveries
    assert_nil mailbox_item.reload.leased_to_agent_session
    assert_nil mailbox_item.leased_to_execution_session
  end
end
