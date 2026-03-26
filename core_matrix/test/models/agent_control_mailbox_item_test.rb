require "test_helper"

class AgentControlMailboxItemTest < ActiveSupport::TestCase
  test "matches the authenticated deployment target and detects stale leases" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_installation: context[:agent_installation],
      agent_task_run: agent_task_run,
      payload: { "task" => "turn_step" }
    )

    assert mailbox_item.valid?
    assert mailbox_item.targets?(context[:deployment])

    mailbox_item.update!(
      status: "leased",
      leased_to_agent_deployment: context[:deployment],
      leased_at: Time.current,
      lease_expires_at: 30.seconds.from_now,
      delivery_no: 1
    )

    assert mailbox_item.leased_to?(context[:deployment])

    travel 31.seconds do
      assert mailbox_item.reload.lease_stale?(at: Time.current)
    end
  end

  test "requires deployment targeting to remain inside the targeted agent installation" do
    context = build_agent_control_context!
    other_agent_installation = create_agent_installation!(installation: context[:installation])
    other_environment = create_execution_environment!(installation: context[:installation])
    other_deployment = create_agent_deployment!(
      installation: context[:installation],
      agent_installation: other_agent_installation,
      execution_environment: other_environment
    )

    mailbox_item = AgentControlMailboxItem.new(
      installation: context[:installation],
      target_agent_installation: context[:agent_installation],
      target_agent_deployment: other_deployment,
      item_type: "resource_close_request",
      target_kind: "agent_deployment",
      target_ref: other_deployment.public_id,
      logical_work_id: "close-test",
      attempt_no: 1,
      delivery_no: 0,
      message_id: "close-message-#{next_test_sequence}",
      priority: 0,
      status: "queued",
      available_at: Time.current,
      dispatch_deadline_at: 5.minutes.from_now,
      lease_timeout_seconds: 30,
      payload: { "request_kind" => "turn_interrupt" }
    )

    assert_not mailbox_item.valid?
    assert_includes mailbox_item.errors[:target_agent_deployment], "must belong to the targeted agent installation"
  end
end
