require "test_helper"

class Conversations::CreateManagedChannelConversationTest < ActiveSupport::TestCase
  test "creates a fresh root conversation with managed channel entry policy" do
    context = create_workspace_context!

    conversation = Conversations::CreateManagedChannelConversation.call(
      workspace_agent: context[:workspace_agent],
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      session_metadata: {
        "sender_username" => "alice",
      }
    )

    assert conversation.root?
    assert conversation.interactive?
    assert_equal context[:workspace_agent], conversation.workspace_agent
    assert_equal context[:workspace], conversation.workspace
    assert_equal context[:agent], conversation.agent
    assert_equal Conversation.channel_managed_entry_policy_payload(
      base_policy_payload: context[:workspace_agent].entry_policy_payload,
      purpose: "interactive"
    ), conversation.entry_policy_payload
    assert_equal "Telegram DM @alice", conversation.title
    assert_equal "agent", conversation.title_source
  end

  test "creates a fork-like managed conversation from existing conversation context" do
    context = create_workspace_context!
    source_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    conversation = Conversations::CreateManagedChannelConversation.call(
      source_conversation: source_conversation,
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "42",
      session_metadata: {}
    )

    assert conversation.fork?
    assert_equal source_conversation, conversation.parent_conversation
    assert_equal Conversation.channel_managed_entry_policy_payload(
      base_policy_payload: source_conversation.workspace_agent.entry_policy_payload,
      purpose: source_conversation.purpose
    ), conversation.entry_policy_payload
    assert_equal "Telegram Webhook DM 42", conversation.title
    assert_equal "agent", conversation.title_source
  end
end
