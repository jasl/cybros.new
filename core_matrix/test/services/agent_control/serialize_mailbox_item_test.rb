require "test_helper"

class AgentControl::SerializeMailboxItemTest < ActiveSupport::TestCase
  test "serializes delivery fields with public ids and iso8601 timestamps" do
    context = build_agent_control_context!
    available_at = Time.zone.parse("2026-03-29 19:30:00 UTC")
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent: context[:agent],
      target_agent_definition_version: context[:agent_definition_version],
      available_at: available_at,
      execution_hard_deadline_at: available_at + 5.minutes,
      payload: { "step" => "execute" }
    )

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal mailbox_item.public_id, serialized["item_id"]
    assert_equal available_at.iso8601, serialized["available_at"]
    assert_equal({ "step" => "execute" }, serialized["payload"])
    refute serialized.key?("target_kind")
    refute serialized.key?("target_ref")
    refute serialized.key?("id")
  end

  test "serializes full payload documents for agent requests" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "prepare_round",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
        },
      },
      logical_work_id: "prepare-round:#{context.fetch(:workflow_node).public_id}",
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal "prepare_round", serialized.dig("payload", "request_kind")
    assert_equal context.fetch(:workflow_node).public_id, serialized.dig("payload", "task", "workflow_node_id")
    assert_equal context.fetch(:turn).public_id, serialized.dig("payload", "task", "turn_id")
    assert_equal context.fetch(:agent).public_id, serialized.dig("payload", "runtime_context", "agent_id")
    assert_equal context.fetch(:user).public_id, serialized.dig("payload", "runtime_context", "user_id")
  end

  test "serializes supervision control mailbox requests with conversation control metadata and scoped runtime context" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      request_kind: "send_guidance_to_subagent",
      target_kind: "subagent_connection",
      target_public_id: "subagent-connection-1",
      lifecycle_state: "queued",
      request_payload: { "content" => "Stop and summarize.", "subagent_connection_id" => "subagent-connection-1" },
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "supervision_guidance",
      payload: {
        "content" => "Stop and summarize.",
        "subagent_connection_id" => "subagent-connection-1",
      },
      dispatch_deadline_at: 5.minutes.from_now
    )

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal "supervision_guidance", serialized.dig("payload", "request_kind")
    assert_equal "send_guidance_to_subagent", serialized.dig("payload", "conversation_control", "request_kind")
    assert_equal "subagent_connection", serialized.dig("payload", "conversation_control", "target_kind")
    assert_equal "subagent-connection-1", serialized.dig("payload", "conversation_control", "target_public_id")
    assert_equal "subagent-connection-1", serialized.dig("payload", "subagent_connection_id")
    assert_equal context.fetch(:agent).public_id, serialized.dig("payload", "runtime_context", "agent_id")
    assert_equal context.fetch(:user).public_id, serialized.dig("payload", "runtime_context", "user_id")
    refute serialized.fetch("payload").key?("task")
  end

  test "serializes supervision guidance mailbox requests matching the shared contract fixture" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true, "side_chat_enabled" => true, "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      request_kind: "send_guidance_to_active_agent",
      target_kind: "conversation",
      target_public_id: context[:conversation].public_id,
      lifecycle_state: "queued",
      request_payload: { "content" => "Stop and summarize." },
      result_payload: {}
    )

    mailbox_item = travel_to(Time.zone.parse("2026-04-10 08:00:00 UTC")) do
      AgentControl::CreateConversationControlRequest.call(
        conversation_control_request: control_request,
        agent_definition_version: context.fetch(:agent_definition_version),
        request_kind: "supervision_guidance",
        payload: { "content" => "Stop and summarize." },
        dispatch_deadline_at: Time.zone.parse("2026-04-10 08:05:00 UTC")
      )
    end

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal supervision_guidance_mailbox_contract_fixture, normalize_supervision_guidance_for_contract(serialized)
  end

  test "serializes execute_tool mailbox requests with the full tool envelope and scoped runtime context" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentRequest.call(
      agent_definition_version: context.fetch(:agent_definition_version),
      request_kind: "execute_tool",
      payload: {
        "task" => {
          "kind" => "turn_step",
          "turn_id" => context.fetch(:turn).public_id,
          "conversation_id" => context.fetch(:conversation).public_id,
          "workflow_run_id" => context.fetch(:workflow_run).public_id,
          "workflow_node_id" => context.fetch(:workflow_node).public_id,
        },
        "tool_call" => {
          "call_id" => "call-serialize",
          "tool_name" => "exec_command",
          "arguments" => { "cmd" => "pwd" },
        },
      },
      logical_work_id: "tool-call:#{context.fetch(:workflow_node).public_id}:call-serialize",
      attempt_no: 1,
      dispatch_deadline_at: 5.minutes.from_now
    )

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal "execute_tool", serialized.dig("payload", "request_kind")
    assert_equal "call-serialize", serialized.dig("payload", "tool_call", "call_id")
    assert_equal "exec_command", serialized.dig("payload", "tool_call", "tool_name")
    assert_equal "pwd", serialized.dig("payload", "tool_call", "arguments", "cmd")
    assert_equal context.fetch(:workflow_node).public_id, serialized.dig("payload", "task", "workflow_node_id")
    assert_equal context.fetch(:agent).public_id, serialized.dig("payload", "runtime_context", "agent_id")
    assert_equal context.fetch(:user).public_id, serialized.dig("payload", "runtime_context", "user_id")
  end

  test "serializes process close requests matching the shared contract fixture" do
    context = build_agent_control_context!
    occurred_at = Time.zone.parse("2026-04-10 09:00:00 UTC")
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
        force_deadline_at: occurred_at + 60.seconds,
        protocol_message_id: "kernel-close-message-id"
      )
    end

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal process_close_request_contract_fixture, normalize_process_close_for_contract(serialized)
  end

  private

  def supervision_guidance_mailbox_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "shared", "fixtures", "contracts", "core_matrix_fenix_supervision_guidance_mailbox_item.json")
      )
    )
  end

  def process_close_request_contract_fixture
    JSON.parse(
      File.read(
        Rails.root.join("..", "shared", "fixtures", "contracts", "core_matrix_fenix_process_run_close_request_mailbox_item.json")
      )
    )
  end

  def normalize_supervision_guidance_for_contract(serialized)
    payload = serialized.fetch("payload").deep_dup
    payload["conversation_control"] = payload.fetch("conversation_control").merge(
      "conversation_control_request_id" => "conversation-control-request-public-id",
      "conversation_id" => "conversation-public-id",
      "target_public_id" => "conversation-public-id"
    )
    payload["runtime_context"] = payload.fetch("runtime_context").merge(
      "agent_id" => "agent-public-id",
      "user_id" => "user-public-id",
      "logical_work_id" => "conversation-control:conversation-control-request-public-id:supervision_guidance",
      "agent_definition_version_id" => "agent-definition-version-public-id"
    )

    serialized.merge(
      "item_id" => "mailbox-item-supervision-public-id",
      "logical_work_id" => "conversation-control:conversation-control-request-public-id:supervision_guidance",
      "protocol_message_id" => "kernel-agent-request-supervision-message-id",
      "payload" => payload
    )
  end

  def normalize_process_close_for_contract(serialized)
    payload = serialized.fetch("payload").deep_dup
    payload["resource_id"] = "process-run-public-id"
    payload["close_request_id"] = "mailbox-item-close-public-id"

    serialized.merge(
      "item_id" => "mailbox-item-close-public-id",
      "logical_work_id" => "close:ProcessRun:process-run-public-id",
      "protocol_message_id" => "kernel-close-message-id",
      "payload" => payload
    )
  end
end
