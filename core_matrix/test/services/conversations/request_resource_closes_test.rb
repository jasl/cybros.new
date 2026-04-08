require "test_helper"

class Conversations::RequestResourceClosesTest < ActiveSupport::TestCase
  test "requests closes only for open resources and anchors deadlines from the provided occurrence time" do
    context = build_agent_control_context!
    open_process = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    already_requested = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    already_requested.update!(
      close_state: "requested",
      close_reason_kind: "conversation_archived",
      close_requested_at: 2.minutes.ago,
      close_grace_deadline_at: 90.seconds.ago,
      close_force_deadline_at: 30.seconds.from_now
    )
    occurred_at = 10.minutes.from_now.change(usec: 0)

    assert_difference("AgentControlMailboxItem.count", 1) do
      Conversations::RequestResourceCloses.call(
        relations: ProcessRun.where(id: [open_process.id, already_requested.id]),
        request_kind: "archive",
        reason_kind: "conversation_archived",
        strictness: "graceful",
        occurred_at: occurred_at
      )
    end

    mailbox_item = AgentControlMailboxItem.order(:created_at).last

    assert_equal open_process.public_id, mailbox_item.payload["resource_id"]
    assert_equal "graceful", mailbox_item.payload["strictness"]
    assert_equal (occurred_at + 30.seconds).iso8601, mailbox_item.payload["grace_deadline_at"]
    assert_equal (occurred_at + 60.seconds).iso8601, mailbox_item.payload["force_deadline_at"]
    assert_equal "requested", open_process.reload.close_state
    assert_equal "requested", already_requested.reload.close_state
  end
end
