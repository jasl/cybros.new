require "test_helper"

class Conversations::ProgressCloseRequestsTest < ActiveSupport::TestCase
  test "escalates grace-expired close requests to forced strictness" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: process_run,
      request_kind: "archive",
      reason_kind: "conversation_archived",
      strictness: "graceful",
      grace_deadline_at: 2.minutes.ago,
      force_deadline_at: 1.minute.from_now
    )

    Conversations::ProgressCloseRequests.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "forced", mailbox_item.reload.payload["strictness"]
    assert_equal "queued", mailbox_item.status
  end

  test "does not touch active close requests once the resource is already closed" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "background_service",
      timeout_seconds: nil
    )
    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: process_run,
      request_kind: "archive",
      reason_kind: "conversation_archived",
      strictness: "graceful",
      grace_deadline_at: 2.minutes.ago,
      force_deadline_at: 1.minute.from_now
    )
    process_run.update!(
      close_state: "closed",
      close_reason_kind: "conversation_archived",
      close_requested_at: 2.minutes.ago,
      close_grace_deadline_at: 90.seconds.ago,
      close_force_deadline_at: 1.minute.from_now,
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "test" }
    )

    Conversations::ProgressCloseRequests.call(
      conversation: context[:conversation],
      occurred_at: Time.current
    )

    assert_equal "graceful", mailbox_item.reload.payload["strictness"]
    assert_equal "queued", mailbox_item.status
  end
end
