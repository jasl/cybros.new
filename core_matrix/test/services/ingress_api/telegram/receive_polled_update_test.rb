require "test_helper"

class IngressAPI::Telegram::ReceivePolledUpdateTest < ActiveSupport::TestCase
  test "passes polled telegram updates into ingress with telegram_poller request metadata" do
    context = create_telegram_receive_context
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

    result = IngressAPI::Telegram::ReceivePolledUpdate.call(
      channel_connector: context[:channel_connector],
      update: {
        "update_id" => 101,
        "message" => {
          "message_id" => 55,
          "date" => 1_713_612_345,
          "chat" => { "id" => 42, "type" => "private" },
          "from" => { "id" => 42, "username" => "alice" },
          "text" => "hello from poller",
        },
      },
      receive_event: fake_receive_event
    )

    assert_equal "telegram_poller", received.fetch(:request_metadata).fetch("source")
    assert_equal context[:channel_connector].public_id, received.fetch(:request_metadata).fetch("channel_connector_id")
    assert received.fetch(:adapter).respond_to?(:verify_request!)
    assert received.fetch(:adapter).respond_to?(:normalize_envelope)
    assert_equal "transcript_entry", result.handled_via
  end

  private

  def create_telegram_receive_context
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
      credential_ref_payload: {
        "bot_token" => "123:abc",
      },
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
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
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
