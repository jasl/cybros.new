require "test_helper"

class SubagentSessions::RequestCloseTest < ActiveSupport::TestCase
  test "close is idempotent" do
    context = build_agent_control_context!
    session = create_running_subagent_session!(context: context)

    assert_difference("AgentControlMailboxItem.where(item_type: 'resource_close_request').count", 1) do
      SubagentSessions::RequestClose.call(
        subagent_session: session,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupt",
        strictness: "graceful"
      )
    end

    assert_no_difference("AgentControlMailboxItem.where(item_type: 'resource_close_request').count") do
      SubagentSessions::RequestClose.call(
        subagent_session: session.reload,
        request_kind: "turn_interrupt",
        reason_kind: "turn_interrupt",
        strictness: "graceful"
      )
    end

    close_request = AgentControlMailboxItem.where(item_type: "resource_close_request").order(:created_at).last

    assert_equal "requested", session.reload.close_state
    assert session.lifecycle_close_requested?
    assert_equal "SubagentSession", close_request.payload.fetch("resource_type")
    assert_equal session.public_id, close_request.payload.fetch("resource_id")
  end

  private

  def create_running_subagent_session!(context:)
    owner_conversation = context[:conversation]
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "thread",
      execution_environment: context[:execution_environment],
      agent_deployment: context[:agent_deployment],
      addressability: "agent_addressable"
    )

    SubagentSession.create!(
      installation: context[:installation],
      owner_conversation: owner_conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      last_known_status: "running"
    )
  end
end
