require "test_helper"

class ChannelIngressConversationRotationTest < ActionDispatch::IntegrationTest
  test "archived channel conversations rotate on the next inbound webhook message" do
    context = telegram_webhook_context
    archived_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      entry_policy_payload: Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: context[:workspace_agent].entry_policy_payload,
        purpose: "interactive"
      )
    )
    archived_conversation.update!(lifecycle_state: "archived")
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: archived_conversation,
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )

    assert_difference(["Conversation.count", "ChannelInboundMessage.count", "Turn.count", "Message.count"], 1) do
      post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
        params: {
          update_id: 203,
          message: {
            message_id: 156,
            date: 1_713_612_446,
            chat: { id: 42, type: "private" },
            from: { id: 42, username: "alice" },
            text: "hello rotated",
          },
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
        },
        as: :json
    end

    assert_response :ok
    refute_equal archived_conversation, channel_session.reload.conversation
    assert_equal "Telegram Webhook DM @alice", channel_session.conversation.title
    assert_equal "hello rotated", channel_session.conversation.reload.latest_turn.selected_input_message.content
  end

  test "stopped channel conversations do not rotate on the next inbound message" do
    context = telegram_webhook_context
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      entry_policy_payload: Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: context[:workspace_agent].entry_policy_payload,
        purpose: "interactive"
      )
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: conversation,
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )
    turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: Struct.new(:public_id).new("seed-inbound"),
      content: "seed",
      origin_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => channel_session.public_id,
        "external_message_key" => "telegram:chat:42:message:155",
        "external_sender_id" => "42",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    Conversations::RequestTurnInterrupt.call(turn: turn)

    assert_no_difference("Conversation.count") do
      post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
        params: {
          update_id: 204,
          message: {
            message_id: 157,
            date: 1_713_612_447,
            chat: { id: 42, type: "private" },
            from: { id: 42, username: "alice" },
            text: "hello after stop",
          },
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
        },
        as: :json
    end

    assert_equal conversation, channel_session.reload.conversation
    assert_equal 422, response.status
  end

  private

  def telegram_webhook_context
    context = create_workspace_context!
    plaintext_secret, secret_digest = IngressBinding.issue_ingress_secret
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      ingress_secret_digest: secret_digest,
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram_webhook",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Telegram Webhook",
      lifecycle_state: "active",
      credential_ref_payload: {
        "bot_token" => "telegram-bot-token",
      },
      config_payload: {
        "webhook_base_url" => "https://bot.example.com",
      },
      runtime_state_payload: {}
    )

    context.merge(
      plaintext_secret: plaintext_secret,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector
    )
  end
end
