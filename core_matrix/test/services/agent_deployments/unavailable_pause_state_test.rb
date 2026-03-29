require "test_helper"

class AgentDeployments::UnavailablePauseStateTest < ActiveSupport::TestCase
  test "resume restores an unresolved paused blocker snapshot with the wait-state contract shape" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    paused_since = Time.zone.parse("2026-03-29 12:00:00 UTC")
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "agent_unavailable",
      wait_reason_payload: {
        "recovery_state" => "transient_outage",
        "reason" => "heartbeat_missed",
        WorkflowWaitSnapshot::SNAPSHOT_KEY => {
          "wait_reason_kind" => "human_interaction",
          "wait_reason_payload" => { "request_id" => request.public_id },
          "waiting_since_at" => paused_since.iso8601,
          "blocking_resource_type" => "HumanInteractionRequest",
          "blocking_resource_id" => request.public_id,
        },
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentDeployment",
      blocking_resource_id: context[:agent_deployment].public_id
    )

    attributes = AgentDeployments::UnavailablePauseState.resume_attributes(
      workflow_run: context[:workflow_run].reload
    )

    assert_equal(
      {
        wait_state: "waiting",
        wait_reason_kind: "human_interaction",
        wait_reason_payload: { "request_id" => request.public_id },
        waiting_since_at: paused_since,
        blocking_resource_type: "HumanInteractionRequest",
        blocking_resource_id: request.public_id,
      },
      attributes
    )
  end

  test "resume returns ready attributes once the paused blocker has resolved" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "agent_unavailable",
      wait_reason_payload: {
        "recovery_state" => "transient_outage",
        "reason" => "heartbeat_missed",
        WorkflowWaitSnapshot::SNAPSHOT_KEY => {
          "wait_reason_kind" => "human_interaction",
          "wait_reason_payload" => { "request_id" => request.public_id },
          "blocking_resource_type" => "HumanInteractionRequest",
          "blocking_resource_id" => request.public_id,
        },
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentDeployment",
      blocking_resource_id: context[:agent_deployment].public_id
    )
    request.resolve!(resolution_kind: "completed", result_payload: {})

    attributes = AgentDeployments::UnavailablePauseState.resume_attributes(
      workflow_run: context[:workflow_run].reload
    )

    assert_equal Workflows::WaitState.ready_attributes, attributes
  end
end
