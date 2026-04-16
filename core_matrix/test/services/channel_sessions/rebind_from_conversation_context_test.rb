require "test_helper"

module ChannelSessions
end

class ChannelSessions::RebindFromConversationContextTest < ActiveSupport::TestCase
  test "creates a managed child conversation from the selected context and rebinds the channel session" do
    context = create_workspace_context!
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "poller",
      label: "Telegram Poller",
      lifecycle_state: "active",
      credential_ref_payload: { "bot_token" => "123:abc" },
      config_payload: {},
      runtime_state_payload: {}
    )
    original_conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    source_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: original_conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )

    assert_difference("Conversation.count", 1) do
      ChannelSessions::RebindFromConversationContext.call(
        channel_session: channel_session,
        source_conversation: source_conversation
      )
    end

    rebound_conversation = channel_session.reload.conversation
    assert_not_equal source_conversation, rebound_conversation
    assert_equal source_conversation, rebound_conversation.parent_conversation
    assert_equal Conversation.channel_managed_entry_policy_payload(
      base_policy_payload: source_conversation.workspace_agent.entry_policy_payload,
      purpose: source_conversation.purpose
    ), rebound_conversation.entry_policy_payload
    assert_equal true, Conversations::ManagedPolicy.call(conversation: rebound_conversation).fetch("managed")
  end
end
