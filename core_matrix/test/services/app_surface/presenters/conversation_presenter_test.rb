require "test_helper"

module AppSurface
  module Presenters
  end
end

class AppSurface::Presenters::ConversationPresenterTest < ActiveSupport::TestCase
  test "emits only public ids and stable conversation fields" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    payload = AppSurface::Presenters::ConversationPresenter.call(conversation: conversation)

    assert_equal conversation.public_id, payload.fetch("conversation_id")
    assert_equal context[:workspace].public_id, payload.fetch("workspace_id")
    assert_equal context[:agent].public_id, payload.fetch("agent_id")
    assert_equal conversation.kind, payload.fetch("kind")
    assert_equal conversation.purpose, payload.fetch("purpose")
    assert_equal conversation.lifecycle_state, payload.fetch("lifecycle_state")
    refute_includes payload.to_json, %("#{conversation.id}")
  end

  test "emits bare-conversation continuity state without a current epoch" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    payload = AppSurface::Presenters::ConversationPresenter.call(conversation: conversation)

    assert_equal context[:execution_runtime].public_id, payload.fetch("current_execution_runtime_id")
    assert_nil payload["current_execution_epoch_id"]
    assert_equal "not_started", payload.fetch("execution_continuity_state")
  end

  test "emits computed management projection with public ids only" do
    context = create_workspace_context!
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
      platform: "telegram_webhook",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Telegram Webhook",
      lifecycle_state: "active",
      credential_ref_payload: { "bot_token" => "123:abc" },
      config_payload: { "webhook_base_url" => "https://bot.example.com" },
      runtime_state_payload: {}
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "telegram_webhook",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )

    payload = AppSurface::Presenters::ConversationPresenter.call(conversation: conversation)

    assert_equal true, payload.dig("management", "managed")
    assert_equal "channel_ingress", payload.dig("management", "manager_kind")
    assert_equal [channel_session.public_id], payload.dig("management", "channel_session_ids")
    assert_equal [ingress_binding.public_id], payload.dig("management", "ingress_binding_ids")
    assert_equal ["telegram_webhook"], payload.dig("management", "platforms")
    refute_includes payload.to_json, %("#{channel_session.id}")
    refute_includes payload.to_json, %("#{ingress_binding.id}")
  end
end
