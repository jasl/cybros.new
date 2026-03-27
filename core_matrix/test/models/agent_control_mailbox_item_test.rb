require "test_helper"

class AgentControlMailboxItemTest < ActiveSupport::TestCase
  test "execution assignments persist agent-plane routing in durable mailbox columns" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item).reload
    envelope = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal "agent", mailbox_item.attributes["runtime_plane"]
    assert_nil mailbox_item.attributes["target_execution_environment_id"]
    assert_equal context[:agent_installation].public_id, mailbox_item.target_ref
    assert_equal "agent", envelope.fetch("runtime_plane")
    refute envelope.fetch("payload").key?("runtime_plane")
  end

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
      runtime_plane: "agent",
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

  test "environment-plane close work keeps the execution environment as the durable target reference" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      execution_environment: context[:execution_environment],
      kind: "turn_command"
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: process_run,
      request_kind: "turn_interrupt",
      reason_kind: "turn_interrupted",
      strictness: "graceful",
      grace_deadline_at: 30.seconds.from_now,
      force_deadline_at: 60.seconds.from_now
    )

    assert_equal "environment", mailbox_item.attributes["runtime_plane"]
    assert_equal context[:execution_environment].id, mailbox_item.attributes["target_execution_environment_id"]
    assert_equal context[:execution_environment].public_id, mailbox_item.target_ref
  end

  test "agent-plane subagent close work falls back to the workflow turn agent installation when no lease holder exists" do
    context = build_agent_control_context!
    subagent_run = create_subagent_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running"
    )

    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: subagent_run,
      request_kind: "turn_interrupt",
      reason_kind: "turn_interrupted",
      strictness: "graceful",
      grace_deadline_at: 30.seconds.from_now,
      force_deadline_at: 60.seconds.from_now
    )

    assert_equal context[:agent_installation], mailbox_item.target_agent_installation
    assert_equal "agent_installation", mailbox_item.target_kind
    assert_equal context[:agent_installation].public_id, mailbox_item.target_ref
    assert_equal "agent", mailbox_item.attributes["runtime_plane"]
    assert_equal "SubagentRun", mailbox_item.payload.fetch("resource_type")
    assert_equal subagent_run.public_id, mailbox_item.payload.fetch("resource_id")
  end

  test "requires runtime_plane to be declared explicitly instead of inferring it from payload conventions" do
    context = build_agent_control_context!

    mailbox_item = AgentControlMailboxItem.new(
      installation: context[:installation],
      target_agent_installation: context[:agent_installation],
      item_type: "execution_assignment",
      target_kind: "agent_installation",
      target_ref: context[:agent_installation].public_id,
      logical_work_id: "assignment-#{next_test_sequence}",
      attempt_no: 1,
      delivery_no: 0,
      message_id: "kernel-message-#{next_test_sequence}",
      priority: 1,
      status: "queued",
      available_at: Time.current,
      dispatch_deadline_at: 5.minutes.from_now,
      lease_timeout_seconds: 30,
      payload: {
        "agent_task_run_id" => "task-run-#{next_test_sequence}",
      }
    )

    assert_not mailbox_item.valid?
    assert_includes mailbox_item.errors.attribute_names, :runtime_plane
  end
end
