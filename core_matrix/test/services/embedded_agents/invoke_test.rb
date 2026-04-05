require "test_helper"

module EmbeddedAgents
end

class EmbeddedAgents::InvokeTest < ActiveSupport::TestCase
  test "dispatches conversation supervision requests and returns a consistent result" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent_program: context[:agent_program]
    )
    ConversationCapabilityPolicy.create!(
      installation: context[:installation],
      target_conversation: conversation,
      supervision_enabled: true,
      side_chat_enabled: true,
      control_enabled: false,
      policy_payload: {}
    )

    result = EmbeddedAgents::Invoke.call(
      agent_key: "conversation_supervision",
      actor: context[:user],
      target: { "conversation_id" => conversation.public_id },
      input: { "question" => "What are you doing?" }
    )

    assert_instance_of EmbeddedAgents::Result, result
    assert_equal "conversation_supervision", result.agent_key
    assert_equal "ok", result.status
    assert_equal conversation.public_id, result.output.fetch("conversation_id")
    assert_equal true, result.output.fetch("conversation_supervision_allowed")
    assert_equal "builtin", result.responder_kind
  end

  test "rejects raw bigint target identifiers at the entry boundary" do
    context = create_workspace_context!

    error = assert_raises(EmbeddedAgents::Errors::InvalidTargetIdentifier) do
      EmbeddedAgents::Invoke.call(
        agent_key: "conversation_supervision",
        actor: context[:user],
        target: context[:workspace].id,
        input: { "question" => "What are you doing?" }
      )
    end

    assert_equal "target must use public ids", error.message
  end

  test "raises a typed error for unknown agent keys" do
    context = create_workspace_context!

    error = assert_raises(EmbeddedAgents::Errors::UnknownAgentKey) do
      EmbeddedAgents::Invoke.call(
        agent_key: "missing_agent",
        actor: context[:user],
        target: { "conversation_id" => "conversation-public-id" },
        input: {}
      )
    end

    assert_equal "unknown embedded agent key missing_agent", error.message
  end
end
