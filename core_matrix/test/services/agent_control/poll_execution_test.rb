require "test_helper"

class AgentControlPollExecutionTest < ActiveSupport::TestCase
  test "leases execution-runtime-plane work by durable execution runtime columns even when program hints do not match" do
    context = build_agent_control_context!
    other_agent = create_agent!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(execution_runtime_connection: context[:execution_runtime_connection], limit: 10)

    assert_equal [mailbox_item.id], deliveries.map(&:id)
    assert_equal context[:execution_runtime_connection], mailbox_item.reload.leased_to_execution_runtime_connection
    assert_nil mailbox_item.leased_to_agent_connection
  end

  test "does not lease execution-runtime-plane work to an execution runtime connection on the wrong runtime even if payload routing is spoofed" do
    context = build_agent_control_context!
    other_execution_runtime = create_execution_runtime!(installation: context[:installation])
    other_agent = create_agent!(
      installation: context[:installation],
      default_execution_runtime: other_execution_runtime
    )
    wrong_agent_snapshot = create_agent_snapshot!(
      installation: context[:installation],
      agent: other_agent
    )
    wrong_agent_connection = create_agent_connection!(
      installation: context[:installation],
      agent: other_agent,
      agent_snapshot: wrong_agent_snapshot
    )
    wrong_execution_runtime_connection = create_execution_runtime_connection!(
      installation: context[:installation],
      execution_runtime: other_execution_runtime,
      connection_credential_digest: Digest::SHA256.hexdigest("execution-connection-#{next_test_sequence}")
    )
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: other_agent,
      target_execution_runtime: context[:execution_runtime],
      item_type: "resource_close_request",
      control_plane: "execution_runtime",
      payload: {
        "control_plane" => "execution_runtime",
        "execution_runtime_id" => other_execution_runtime.public_id,
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(execution_runtime_connection: wrong_execution_runtime_connection, limit: 10)

    assert_empty deliveries
    assert_nil mailbox_item.reload.leased_to_agent_connection
    assert_nil mailbox_item.leased_to_execution_runtime_connection
    assert_equal wrong_agent_connection.agent_id, other_agent.id
  end

  test "requeues acknowledged close requests as forced once the grace deadline expires" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-28 10:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
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
      execution_runtime_connection: context[:execution_runtime_connection],
      limit: 10,
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal [close_request.id], deliveries.map(&:id)
    assert_equal "leased", close_request.reload.status
    assert_equal "forced", close_request.payload["strictness"]
    assert_equal context[:execution_runtime_connection], close_request.leased_to_execution_runtime_connection
    assert_nil close_request.leased_to_agent_connection
  end

  test "times out acknowledged close requests once the force deadline expires" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-28 11:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime],
      kind: "background_service",
      timeout_seconds: nil
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
      execution_runtime_connection: context[:execution_runtime_connection],
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
