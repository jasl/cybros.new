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

  test "prioritizes resource close requests ahead of normal execution work" do
    context = build_agent_control_context!
    scenario_builder = MailboxScenarioBuilder.new(self)
    assignment = scenario_builder.execution_assignment!(context: context).fetch(:mailbox_item)
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment]
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )
    close_request = scenario_builder.close_request!(context: context, resource: process_run).fetch(:mailbox_item)

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_equal [close_request.id, assignment.id], deliveries.map(&:id)
  end

  test "leases environment-plane work by durable execution environment columns even when agent-installation hints do not match" do
    context = build_agent_control_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: other_agent_installation,
      target_execution_environment: context[:execution_environment],
      item_type: "resource_close_request",
      runtime_plane: "environment",
      target_kind: "agent_installation",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(deployment: context[:deployment], limit: 10)

    assert_equal [mailbox_item.id], deliveries.map(&:id)
    assert_equal context[:deployment], mailbox_item.reload.leased_to_agent_deployment
  end

  test "does not lease environment-plane work to a deployment on the wrong execution environment even if payload routing is spoofed" do
    context = build_agent_control_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    other_execution_environment = create_execution_environment!(installation: context[:installation])
    wrong_deployment = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: other_agent_installation,
      execution_environment: other_execution_environment,
      bootstrap_state: "active",
      health_status: "healthy",
      last_heartbeat_at: Time.current
    )
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: other_agent_installation,
      target_execution_environment: context[:execution_environment],
      item_type: "resource_close_request",
      runtime_plane: "environment",
      target_kind: "agent_installation",
      payload: {
        "runtime_plane" => "environment",
        "execution_environment_id" => other_execution_environment.public_id,
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(deployment: wrong_deployment, limit: 10)

    assert_empty deliveries
    assert_nil mailbox_item.reload.leased_to_agent_deployment
  end

  test "requeues acknowledged close requests as forced once the grace deadline expires" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-28 10:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )

    close_request = travel_to(occurred_at) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: process_run,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupted",
        strictness: "graceful",
        grace_deadline_at: occurred_at + 30.seconds,
        force_deadline_at: occurred_at + 60.seconds
      )
    end

    process_run.update!(
      close_state: "acknowledged",
      close_acknowledged_at: occurred_at + 5.seconds
    )
    close_request.update!(
      status: "acked",
      acked_at: occurred_at + 5.seconds
    )

    deliveries = AgentControl::Poll.call(
      deployment: context[:replacement_deployment],
      limit: 10,
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal [close_request.id], deliveries.map(&:id)
    assert_equal "leased", close_request.reload.status
    assert_equal "forced", close_request.payload["strictness"]
    assert_equal context[:replacement_deployment], close_request.leased_to_agent_deployment
  end

  test "times out acknowledged close requests once the force deadline expires" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-28 11:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )

    close_request = travel_to(occurred_at) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: process_run,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupted",
        strictness: "graceful",
        grace_deadline_at: occurred_at + 30.seconds,
        force_deadline_at: occurred_at + 60.seconds
      )
    end

    process_run.update!(
      close_state: "acknowledged",
      close_acknowledged_at: occurred_at + 5.seconds
    )
    close_request.update!(
      status: "acked",
      acked_at: occurred_at + 5.seconds
    )

    deliveries = AgentControl::Poll.call(
      deployment: context[:replacement_deployment],
      limit: 10,
      occurred_at: occurred_at + 61.seconds
    )

    assert_empty deliveries
    assert_equal "completed", close_request.reload.status
    assert process_run.reload.close_failed?
    assert process_run.lost?
    assert_equal "timed_out_forced", process_run.close_outcome_kind
    assert_equal "force_deadline_elapsed", process_run.close_outcome_payload["reason"]
  end
end
