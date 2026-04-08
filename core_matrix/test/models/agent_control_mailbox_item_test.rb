require "test_helper"

class AgentControlMailboxItemTest < ActiveSupport::TestCase
  test "execution assignments persist program-plane routing in durable mailbox columns" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item).reload
    envelope = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal "program", mailbox_item.attributes["control_plane"]
    assert_nil mailbox_item.attributes["target_executor_program_id"]
    assert_equal "program", envelope.fetch("control_plane")
    refute envelope.key?("target_kind")
    refute envelope.key?("target_ref")
    refute envelope.fetch("payload").key?("control_plane")
  end

  test "matches the authenticated deployment target and detects stale leases" do
    context = build_agent_control_context!
    agent_task_run = create_agent_task_run!(workflow_node: context[:workflow_node])
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      agent_task_run: agent_task_run,
      payload: { "task" => "turn_step" }
    )

    assert mailbox_item.valid?
    assert mailbox_item.targets?(context[:deployment])

    mailbox_item.update!(
      status: "leased",
      leased_to_agent_session: context[:agent_session],
      leased_at: Time.current,
      lease_expires_at: 30.seconds.from_now,
      delivery_no: 1
    )

    assert mailbox_item.leased_to?(context[:deployment])

    travel 31.seconds do
      assert mailbox_item.reload.lease_stale?(at: Time.current)
    end
  end

  test "loads payload from payload_document when the mailbox item externalizes a large request" do
    context = build_agent_control_context!
    payload_document = JsonDocuments::Store.call(
      installation: context[:installation],
      document_kind: "agent_program_request",
      payload: {
        "request_kind" => "prepare_round",
        "conversation_projection" => {
          "messages" => [{ "role" => "user", "content" => "Input" }],
        },
      }
    )
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: context[:deployment],
      workflow_node: context[:workflow_node],
      execution_contract: context[:turn].execution_contract,
      item_type: "agent_program_request",
      control_plane: "program",
      logical_work_id: "prepare-round-#{next_test_sequence}",
      payload_document: payload_document,
      payload: { "request_kind" => "prepare_round" }
    )

    assert_equal payload_document.payload.fetch("conversation_projection"), mailbox_item.payload.fetch("conversation_projection")
    assert_equal({ "request_kind" => "prepare_round" }, mailbox_item.payload_body)
    assert_equal "prepare_round", mailbox_item.payload.fetch("request_kind")
    assert_equal mailbox_item.logical_work_id, mailbox_item.payload.dig("runtime_context", "logical_work_id")
    assert_equal mailbox_item.attempt_no, mailbox_item.payload.dig("runtime_context", "attempt_no")
    assert_equal mailbox_item.control_plane, mailbox_item.payload.dig("runtime_context", "control_plane")
    assert_equal context[:deployment].public_id, mailbox_item.payload.dig("runtime_context", "agent_program_version_id")
    assert_equal context[:agent_program].public_id, mailbox_item.payload.dig("runtime_context", "agent_program_id")
    assert_equal context[:user].public_id, mailbox_item.payload.dig("runtime_context", "user_id")
  end

  test "requires deployment targeting to remain inside the targeted agent program" do
    context = build_agent_control_context!
    other_agent_program = create_agent_program!(installation: context[:installation])
    other_deployment = create_agent_program_version!(
      installation: context[:installation],
      agent_program: other_agent_program
    )

    mailbox_item = AgentControlMailboxItem.new(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: other_deployment,
      item_type: "resource_close_request",
      control_plane: "program",
      logical_work_id: "close-test",
      attempt_no: 1,
      delivery_no: 0,
      protocol_message_id: "close-message-#{next_test_sequence}",
      priority: 0,
      status: "queued",
      available_at: Time.current,
      dispatch_deadline_at: 5.minutes.from_now,
      lease_timeout_seconds: 30,
      payload: { "request_kind" => "turn_interrupt" }
    )

    assert_not mailbox_item.valid?
    assert_includes mailbox_item.errors[:target_agent_program_version], "must belong to the targeted agent program"
  end

  test "executor-plane close work keeps the executor program as the durable target reference" do
    context = build_agent_control_context!
    process_run = create_process_run!(
      workflow_node: context[:workflow_node],
      executor_program: context[:executor_program],
      kind: "background_service",
      timeout_seconds: nil
    )
    Leases::Acquire.call(
      leased_resource: process_run,
      holder_key: context[:executor_session].public_id,
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

    assert_equal "executor", mailbox_item.attributes["control_plane"]
    assert_equal context[:executor_program].id, mailbox_item.attributes["target_executor_program_id"]
    refute_respond_to mailbox_item, :target_ref
  end

  test "program-plane subagent session close work falls back to the owner conversation agent program when no lease holder exists" do
    context = build_agent_control_context!
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      kind: "fork",
      agent_program: context[:agent_program],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )

    mailbox_item = AgentControl::CreateResourceCloseRequest.call(
      resource: subagent_session,
      request_kind: "turn_interrupt",
      reason_kind: "turn_interrupted",
      strictness: "graceful",
      grace_deadline_at: 30.seconds.from_now,
      force_deadline_at: 60.seconds.from_now
    )

    assert_equal context[:agent_program], mailbox_item.target_agent_program
    refute_respond_to mailbox_item, :target_kind
    refute_respond_to mailbox_item, :target_ref
    assert_equal "program", mailbox_item.attributes["control_plane"]
    assert_equal "SubagentSession", mailbox_item.payload.fetch("resource_type")
    assert_equal subagent_session.public_id, mailbox_item.payload.fetch("resource_id")
  end

  test "close request creation rolls back resource state when mailbox persistence fails" do
    context = build_agent_control_context!
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: context[:conversation],
      kind: "fork",
      agent_program: context[:agent_program],
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: context[:conversation],
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    protocol_message_id = "duplicate-close-message"

    create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      item_type: "resource_close_request",
      control_plane: "program",
      logical_work_id: "close-test-#{next_test_sequence}",
      protocol_message_id: protocol_message_id,
      priority: 0,
      payload: { "request_kind" => "turn_interrupt" }
    )

    assert_raises(ActiveRecord::RecordInvalid) do
      AgentControl::CreateResourceCloseRequest.call(
        resource: subagent_session,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupted",
        strictness: "graceful",
        grace_deadline_at: 30.seconds.from_now,
        force_deadline_at: 60.seconds.from_now,
        protocol_message_id: protocol_message_id
      )
    end

    assert subagent_session.reload.close_open?
    assert_nil subagent_session.close_reason_kind
    assert_nil subagent_session.close_requested_at
  end

  test "requires control_plane to be declared explicitly instead of inferring it from payload conventions" do
    context = build_agent_control_context!

    mailbox_item = AgentControlMailboxItem.new(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      item_type: "execution_assignment",
      logical_work_id: "assignment-#{next_test_sequence}",
      attempt_no: 1,
      delivery_no: 0,
      protocol_message_id: "kernel-message-#{next_test_sequence}",
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
    assert_includes mailbox_item.errors.attribute_names, :control_plane
  end

  test "rejects invalid control-plane values instead of normalizing them" do
    context = build_agent_control_context!
    mailbox_item = AgentControlMailboxItem.new(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      item_type: "execution_assignment",
      control_plane: "invalid",
      logical_work_id: "assignment-#{next_test_sequence}",
      attempt_no: 1,
      delivery_no: 0,
      protocol_message_id: "kernel-message-#{next_test_sequence}",
      priority: 1,
      status: "queued",
      available_at: Time.current,
      dispatch_deadline_at: 5.minutes.from_now,
      lease_timeout_seconds: 30,
      payload: {
        "request_kind" => "execution_assignment",
      }
    )

    assert_not mailbox_item.valid?
    assert_includes mailbox_item.errors[:control_plane], "is not included in the list"
  end
end
