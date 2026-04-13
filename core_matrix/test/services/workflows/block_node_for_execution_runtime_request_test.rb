require "test_helper"

class Workflows::BlockNodeForExecutionRuntimeRequestTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "persists execution-runtime wait payloads through the cold wait detail row" do
    context = build_agent_control_context!(workflow_node_key: "turn_step", workflow_node_type: "turn_step")
    workflow_node = context.fetch(:workflow_node)
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    mailbox_item = AgentControlMailboxItem.create!(
      installation: context.fetch(:installation),
      target_agent: context.fetch(:agent),
      target_execution_runtime: context.fetch(:execution_runtime),
      workflow_node: workflow_node,
      item_type: "execution_assignment",
      control_plane: "execution_runtime",
      logical_work_id: "runtime:#{workflow_node.public_id}",
      attempt_no: 1,
      protocol_message_id: "runtime-request-#{next_test_sequence}",
      status: "queued",
      available_at: Time.current,
      dispatch_deadline_at: 2.minutes.from_now,
      lease_timeout_seconds: 120,
      payload: {}
    )

    result = Workflows::BlockNodeForExecutionRuntimeRequest.call(
      workflow_node: workflow_node,
      mailbox_item: mailbox_item,
      request_kind: "execute_runtime_tool",
      logical_work_id: "runtime:#{workflow_node.public_id}",
      deadline_at: mailbox_item.dispatch_deadline_at,
      occurred_at: Time.current
    )

    workflow_run = context.fetch(:workflow_run).reload

    assert_equal "execution_runtime_request", workflow_run.wait_reason_kind
    assert_equal mailbox_item.public_id, workflow_run.wait_reason_payload["mailbox_item_id"]
    assert_equal mailbox_item.public_id, workflow_run.workflow_run_wait_detail.wait_reason_payload["mailbox_item_id"]
    assert_equal mailbox_item.public_id, result.mailbox_item.public_id
  end
end
