require "test_helper"

class AgentControl::SerializeMailboxItemTest < ActiveSupport::TestCase
  test "serializes delivery fields with public ids and iso8601 timestamps" do
    context = build_agent_control_context!
    available_at = Time.zone.parse("2026-03-29 19:30:00 UTC")
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: context[:deployment],
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

  test "serializes full payload documents for agent program requests" do
    context = build_agent_control_context!
    mailbox_item = AgentControl::CreateAgentProgramRequest.call(
      agent_program_version: context.fetch(:deployment),
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
    assert_equal context.fetch(:agent_program).public_id, serialized.dig("payload", "runtime_context", "agent_program_id")
    assert_equal context.fetch(:user).public_id, serialized.dig("payload", "runtime_context", "user_id")
  end

  test "serializes supervision control mailbox requests with conversation control metadata and scoped runtime context" do
    context = build_agent_control_context!
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
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
      request_kind: "send_guidance_to_subagent",
      target_kind: "subagent_session",
      target_public_id: "subagent-session-1",
      lifecycle_state: "queued",
      request_payload: { "content" => "Stop and summarize.", "subagent_session_id" => "subagent-session-1" },
      result_payload: {}
    )
    mailbox_item = AgentControl::CreateConversationControlRequest.call(
      conversation_control_request: control_request,
      agent_program_version: context.fetch(:deployment),
      request_kind: "supervision_guidance",
      payload: {
        "content" => "Stop and summarize.",
        "subagent_session_id" => "subagent-session-1",
      },
      dispatch_deadline_at: 5.minutes.from_now
    )

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal "supervision_guidance", serialized.dig("payload", "request_kind")
    assert_equal "send_guidance_to_subagent", serialized.dig("payload", "conversation_control", "request_kind")
    assert_equal "subagent_session", serialized.dig("payload", "conversation_control", "target_kind")
    assert_equal "subagent-session-1", serialized.dig("payload", "conversation_control", "target_public_id")
    assert_equal "subagent-session-1", serialized.dig("payload", "subagent_session_id")
    assert_equal context.fetch(:agent_program).public_id, serialized.dig("payload", "runtime_context", "agent_program_id")
    assert_equal context.fetch(:user).public_id, serialized.dig("payload", "runtime_context", "user_id")
    refute serialized.fetch("payload").key?("task")
  end
end
