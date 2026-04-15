require "test_helper"

class ClawBotSDK::Weixin::ContextTokenStoreTest < ActiveSupport::TestCase
  test "stores and fetches the latest context token on the bound channel session" do
    channel_session = create_weixin_session!

    ClawBotSDK::Weixin::ContextTokenStore.store!(
      channel_session: channel_session,
      context_token: "ctx-1"
    )

    assert_equal "ctx-1", channel_session.reload.session_metadata["context_token"]
    assert_equal "ctx-1", ClawBotSDK::Weixin::ContextTokenStore.fetch(channel_session: channel_session)
  end

  private

  def create_weixin_session!
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
      platform: "weixin",
      driver: "claw_bot_sdk_weixin",
      transport_kind: "poller",
      label: "Weixin Bot",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )

    ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "weixin",
      peer_kind: "dm",
      peer_id: "wx-user-1",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )
  end
end
