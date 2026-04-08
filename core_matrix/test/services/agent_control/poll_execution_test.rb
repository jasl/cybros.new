require "test_helper"

class AgentControlPollExecutionTest < ActiveSupport::TestCase
  test "leases executor-plane work by durable executor program columns even when program hints do not match" do
    context = build_agent_control_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
      payload: {
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(executor_session: context[:executor_session], limit: 10)

    assert_equal [mailbox_item.id], deliveries.map(&:id)
    assert_equal context[:executor_session], mailbox_item.reload.leased_to_executor_session
    assert_nil mailbox_item.leased_to_agent_session
  end

  test "does not lease executor-plane work to an executor session on the wrong runtime even if payload routing is spoofed" do
    context = build_agent_control_context!
    other_executor_program = create_executor_program!(installation: context[:installation])
    other_agent_program = create_agent_program!(
      installation: context[:installation],
      default_executor_program: other_executor_program
    )
    wrong_deployment = create_agent_program_version!(
      installation: context[:installation],
      agent_program: other_agent_program
    )
    wrong_agent_session = create_agent_session!(
      installation: context[:installation],
      agent_program: other_agent_program,
      agent_program_version: wrong_deployment
    )
    wrong_executor_session = create_executor_session!(
      installation: context[:installation],
      executor_program: other_executor_program,
      session_credential_digest: Digest::SHA256.hexdigest("execution-session-#{next_test_sequence}")
    )
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: other_agent_program,
      target_executor_program: context[:executor_program],
      item_type: "resource_close_request",
      control_plane: "executor",
      payload: {
        "control_plane" => "executor",
        "executor_program_id" => other_executor_program.public_id,
        "resource_type" => "ProcessRun",
        "resource_id" => "process-#{next_test_sequence}",
        "request_kind" => "turn_interrupt",
        "reason_kind" => "operator_stop",
      }
    )

    deliveries = AgentControl::Poll.call(executor_session: wrong_executor_session, limit: 10)

    assert_empty deliveries
    assert_nil mailbox_item.reload.leased_to_agent_session
    assert_nil mailbox_item.leased_to_executor_session
    assert_equal wrong_agent_session.agent_program_id, other_agent_program.id
  end

  test "requeues acknowledged close requests as forced once the grace deadline expires" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-28 10:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
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
      executor_session: context[:executor_session],
      limit: 10,
      occurred_at: occurred_at + 31.seconds
    )

    assert_equal [close_request.id], deliveries.map(&:id)
    assert_equal "leased", close_request.reload.status
    assert_equal "forced", close_request.payload["strictness"]
    assert_equal context[:executor_session], close_request.leased_to_executor_session
    assert_nil close_request.leased_to_agent_session
  end

  test "times out acknowledged close requests once the force deadline expires" do
    context = build_rotated_runtime_context!
    occurred_at = Time.zone.parse("2026-03-28 11:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
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
      executor_session: context[:executor_session],
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
