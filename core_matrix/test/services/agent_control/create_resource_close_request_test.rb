require "test_helper"

class AgentControl::CreateResourceCloseRequestTest < ActiveSupport::TestCase
  test "creates an execution-plane close request with durable execution runtime targeting" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-03-29 18:00:00 UTC")
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_runtime: context[:execution_runtime]
    )

    mailbox_item = travel_to(occurred_at) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: process_run,
        request_kind: "turn_interrupt",
        reason_kind: "operator_stop",
        strictness: "graceful",
        grace_deadline_at: occurred_at + 30.seconds,
        force_deadline_at: occurred_at + 60.seconds
      )
    end

    assert_equal "resource_close_request", mailbox_item.item_type
    assert mailbox_item.execution_plane?
    assert_equal context[:execution_runtime], mailbox_item.target_execution_runtime
    assert_nil mailbox_item.target_agent_program_version
    refute_respond_to mailbox_item, :target_ref
    assert_equal mailbox_item.public_id, mailbox_item.payload["close_request_id"]
    assert_equal "ProcessRun", mailbox_item.payload["resource_type"]
    assert_equal process_run.public_id, mailbox_item.payload["resource_id"]
    assert process_run.reload.close_requested?
    assert_equal occurred_at, process_run.close_requested_at
  end

  test "rejects unsupported close resources" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      agent_program: context[:agent_program]
    )

    error = assert_raises(ArgumentError) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: conversation,
        request_kind: "turn_interrupt",
        reason_kind: "operator_stop",
        strictness: "graceful",
        grace_deadline_at: 30.seconds.from_now,
        force_deadline_at: 60.seconds.from_now
      )
    end

    assert_includes error.message, "unsupported close resource Conversation"
  end
end
