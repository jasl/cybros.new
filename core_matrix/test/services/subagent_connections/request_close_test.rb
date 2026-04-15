require "test_helper"

class SubagentConnections::RequestCloseTest < ActiveSupport::TestCase
  test "close is idempotent" do
    context = build_agent_control_context!
    session = create_running_subagent_connection!(context: context)

    assert_difference("AgentControlMailboxItem.where(item_type: 'resource_close_request').count", 1) do
      SubagentConnections::RequestClose.call(
        subagent_connection: session,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupt",
        strictness: "graceful"
      )
    end

    assert_no_difference("AgentControlMailboxItem.where(item_type: 'resource_close_request').count") do
      SubagentConnections::RequestClose.call(
        subagent_connection: session.reload,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupt",
        strictness: "graceful"
      )
    end

    close_request = AgentControlMailboxItem.where(item_type: "resource_close_request").order(:created_at).last

    assert_equal "requested", session.reload.close_state
    assert_equal "close_requested", session.derived_close_status
    assert_equal "SubagentConnection", close_request.payload.fetch("resource_type")
    assert_equal session.public_id, close_request.payload.fetch("resource_id")
  end

  test "records completion on a linked conversation control request" do
    context = build_agent_control_context!
    session = create_running_subagent_connection!(context: context)
    supervision_session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "control_enabled" => true },
      last_snapshot_at: Time.current
    )
    control_request = ConversationControlRequest.create!(
      installation: context[:installation],
      conversation_supervision_session: supervision_session,
      target_conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      request_kind: "request_subagent_close",
      target_kind: "subagent_connection",
      target_public_id: session.public_id,
      lifecycle_state: "queued",
      request_payload: {},
      result_payload: {}
    )

    SubagentConnections::RequestClose.call(
      subagent_connection: session,
      request_kind: "request_subagent_close",
      reason_kind: "supervision_subagent_close_requested",
      strictness: "graceful",
      conversation_control_request: control_request
    )

    assert_equal "completed", control_request.reload.lifecycle_state
    assert_equal session.public_id, control_request.result_payload["subagent_connection_id"]
  end

  private

  def create_running_subagent_connection!(context:)
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      entry_policy_payload: agent_internal_entry_policy_payload
    )

    SubagentConnection.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      user: child_conversation.user,
      workspace: child_conversation.workspace,
      agent: child_conversation.agent,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
  end
end
