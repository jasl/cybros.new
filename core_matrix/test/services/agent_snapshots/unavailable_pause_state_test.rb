require "test_helper"

class AgentSnapshots::UnavailablePauseStateTest < ActiveSupport::TestCase
  test "resume restores an unresolved paused blocker snapshot with the wait-state contract shape" do
    context = build_human_interaction_context!
    request = HumanInteractions::Request.call(
      request_type: "HumanTaskRequest",
      workflow_node: context[:workflow_node],
      blocking: true,
      request_payload: { "instructions" => "Need operator input" }
    )
    paused_since = Time.zone.parse("2026-03-29 12:00:00 UTC")
    snapshot_document = JsonDocuments::Store.call(
      installation: context[:workflow_run].installation,
      document_kind: WorkflowWaitSnapshot::DOCUMENT_KIND,
      payload: {
        "wait_reason_kind" => "human_interaction",
        "wait_reason_payload" => {},
        "waiting_since_at" => paused_since.iso8601,
        "blocking_resource_type" => "HumanInteractionRequest",
        "blocking_resource_id" => request.public_id,
      }
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "agent_unavailable",
      wait_reason_payload: {},
      recovery_state: "transient_outage",
      recovery_reason: "heartbeat_missed",
      wait_snapshot_document: snapshot_document,
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentSnapshot",
      blocking_resource_id: context[:agent_snapshot].public_id
    )

    attributes = AgentSnapshots::UnavailablePauseState.resume_attributes(
      workflow_run: context[:workflow_run].reload
    )

    assert_equal(
      {
        wait_state: "waiting",
        wait_reason_kind: "human_interaction",
        wait_reason_payload: {},
        recovery_state: nil,
        recovery_reason: nil,
        recovery_drift_reason: nil,
        recovery_agent_task_run_public_id: nil,
        wait_snapshot_document: nil,
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
    snapshot_document = JsonDocuments::Store.call(
      installation: context[:workflow_run].installation,
      document_kind: WorkflowWaitSnapshot::DOCUMENT_KIND,
      payload: {
        "wait_reason_kind" => "human_interaction",
        "wait_reason_payload" => {},
        "blocking_resource_type" => "HumanInteractionRequest",
        "blocking_resource_id" => request.public_id,
      }
    )
    context[:workflow_run].update!(
      wait_state: "waiting",
      wait_reason_kind: "agent_unavailable",
      wait_reason_payload: {},
      recovery_state: "transient_outage",
      recovery_reason: "heartbeat_missed",
      wait_snapshot_document: snapshot_document,
      waiting_since_at: Time.current,
      blocking_resource_type: "AgentSnapshot",
      blocking_resource_id: context[:agent_snapshot].public_id
    )
    request.resolve!(resolution_kind: "completed", result_payload: {})

    attributes = AgentSnapshots::UnavailablePauseState.resume_attributes(
      workflow_run: context[:workflow_run].reload
    )

    assert_equal Workflows::WaitState.ready_attributes, attributes
  end
end
