require "test_helper"

module EmbeddedAgents
  module ConversationObservation
  end
end

class EmbeddedAgents::ConversationObservation::AuthorityTest < ActiveSupport::TestCase
  test "permits the owner on their own conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    authority = EmbeddedAgents::ConversationObservation::Authority.call(
      actor: context[:user],
      conversation: conversation
    )

    assert_predicate authority, :allowed?
    assert_equal conversation, authority.conversation
  end

  test "rejects raw bigint conversation identifiers at the entry boundary" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    error = assert_raises(EmbeddedAgents::Errors::InvalidTargetIdentifier) do
      EmbeddedAgents::ConversationObservation::Authority.call(
        actor: context[:user],
        conversation_id: conversation.id
      )
    end

    assert_equal "conversation_id must use public ids", error.message
  end

  test "rejects stringified raw bigint conversation identifiers at the entry boundary" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )

    error = assert_raises(EmbeddedAgents::Errors::InvalidTargetIdentifier) do
      EmbeddedAgents::ConversationObservation::Authority.call(
        actor: context[:user],
        conversation_id: conversation.id.to_s
      )
    end

    assert_equal "conversation_id must use public ids", error.message
  end
end
