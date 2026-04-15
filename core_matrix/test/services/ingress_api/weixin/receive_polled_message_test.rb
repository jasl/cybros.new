require "test_helper"

class IngressAPI::Weixin::ReceivePolledMessageTest < ActiveSupport::TestCase
  test "persists the newest context token on an existing bound session before dispatching ingress" do
    context = create_weixin_receive_context
    received = nil
    fake_receive_event = lambda do |**kwargs|
      received = kwargs
      IngressAPI::Result.handled(
        handled_via: "transcript_entry",
        trace: ["normalized"],
        envelope: nil,
        conversation: context[:conversation],
        channel_session: context[:channel_session],
        request_metadata: kwargs.fetch(:request_metadata)
      )
    end

    result = IngressAPI::Weixin::ReceivePolledMessage.call(
      channel_connector: context[:channel_connector],
      message: {
        "message_id" => "wx-msg-1",
        "from_user_id" => "wx-user-1",
        "create_time_ms" => 1_713_600_000_000,
        "context_token" => "ctx-2",
        "item_list" => [
          { "type" => 1, "text_item" => { "text" => "hello from weixin" } }
        ]
      },
      receive_event: fake_receive_event
    )

    assert_equal "ctx-2", context[:channel_session].reload.session_metadata["context_token"]
    assert_equal "weixin_poller", received.fetch(:request_metadata).fetch("source")
    assert received.fetch(:adapter).respond_to?(:verify_request!)
    assert received.fetch(:adapter).respond_to?(:normalize_envelope)
    assert_equal "transcript_entry", result.handled_via
  end

  private

  def create_weixin_receive_context
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
      runtime_state_payload: {
        "base_url" => "https://weixin.example",
        "bot_token" => "bot-token"
      }
    )
    conversation = create_conversation_record!(
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
      conversation: conversation,
      platform: "weixin",
      peer_kind: "dm",
      peer_id: "wx-user-1",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      channel_session: channel_session
    )
  end
end
