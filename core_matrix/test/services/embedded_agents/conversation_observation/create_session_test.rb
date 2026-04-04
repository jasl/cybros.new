require "test_helper"

class EmbeddedAgents::ConversationObservation::CreateSessionTest < ActiveSupport::TestCase
  test "creates an observation session for an authorized actor" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    session = EmbeddedAgents::ConversationObservation::CreateSession.call(
      actor: context[:user],
      conversation: conversation
    )

    assert_equal conversation, session.target_conversation
    assert_equal context[:user], session.initiator
    assert_equal "open", session.lifecycle_state
    assert_equal({ "observe" => true, "control_enabled" => false }, session.capability_policy_snapshot)
  end

  test "raises a typed error for an unauthorized actor" do
    context = create_workspace_context!
    other_user = create_user!(installation: context[:installation])
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    error = assert_raises(EmbeddedAgents::Errors::UnauthorizedObservation) do
      EmbeddedAgents::ConversationObservation::CreateSession.call(
        actor: other_user,
        conversation: conversation
      )
    end

    assert_equal "not allowed to observe conversation", error.message
  end
end
