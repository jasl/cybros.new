require "test_helper"

class IngressAPI::CommandSurfaceTest < ActiveSupport::TestCase
  test "report returns a sidecar result and dispatches an outbound reply without creating a turn" do
    context = command_context
    adapter = fake_adapter_for(context, text: "/report")

    assert_no_difference("Turn.count") do
      assert_difference("ChannelDelivery.count", 1) do
        result = IngressAPI::ReceiveEvent.call(
          adapter: adapter,
          raw_payload: { "update_id" => 1001 },
          request_metadata: { "source" => "telegram_webhook" }
        )

        assert result.handled?
        assert_equal "sidecar_query", result.handled_via
      end
    end

    delivery = ChannelDelivery.order(:id).last
    assert_equal context[:conversation], delivery.conversation
    assert_predicate delivery.payload["text"], :present?
    assert_equal "telegram:chat:telegram-user-1:message:1001", delivery.reply_to_external_message_key
  end

  test "btw returns a read only sidecar answer and dispatches it back to telegram" do
    context = command_context
    adapter = fake_adapter_for(context, text: "/btw what changed most recently?")

    assert_no_difference("Turn.count") do
      assert_difference("ChannelDelivery.count", 1) do
        result = IngressAPI::ReceiveEvent.call(
          adapter: adapter,
          raw_payload: { "update_id" => 1002 },
          request_metadata: { "source" => "telegram_webhook" }
        )

        assert result.handled?
        assert_equal "sidecar_query", result.handled_via
      end
    end

    delivery = ChannelDelivery.order(:id).last
    assert_predicate delivery.payload["text"], :present?
    assert_equal "telegram:chat:telegram-user-1:message:1002", delivery.reply_to_external_message_key
  end

  test "stop interrupts same sender work without creating transcript or sidecar output" do
    context = command_context
    active_turn = Turns::StartChannelIngressTurn.call(
      conversation: context[:conversation],
      channel_inbound_message: Struct.new(:public_id).new("channel-inbound-1"),
      content: "active work",
      origin_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => context[:channel_session].public_id,
        "external_sender_id" => "telegram-user-1",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )
    adapter = fake_adapter_for(context, text: "/stop", external_message_id: 1003)

    assert_no_difference(["Turn.count", "ChannelDelivery.count"]) do
      result = IngressAPI::ReceiveEvent.call(
        adapter: adapter,
        raw_payload: { "update_id" => 1003 },
        request_metadata: { "source" => "telegram_webhook" }
      )

      assert result.handled?
      assert_equal "control_command", result.handled_via
    end

    assert active_turn.reload.cancellation_requested_at.present? || active_turn.reload.canceled?
  end

  private

  def command_context
    context = create_workspace_context!
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: {
        "allow_app_entry" => true,
        "allow_external_entry" => true,
      }
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Primary Telegram",
      lifecycle_state: "active",
      credential_ref_payload: {
        "bot_token" => "telegram-bot-token"
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
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {}
    )

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      channel_session: channel_session
    )
  end

  def fake_adapter_for(context, text:, external_message_id: text.include?("/report") ? 1001 : 1002)
    envelope = IngressAPI::Envelope.new(
      platform: "telegram",
      driver: "telegram_bot_api",
      ingress_binding_public_id: context[:ingress_binding].public_id,
      channel_connector_public_id: context[:channel_connector].public_id,
      external_event_key: "telegram:update:#{text.hash.abs}",
      external_message_key: "telegram:chat:telegram-user-1:message:#{external_message_id}",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      text: text,
      attachments: [],
      reply_to_external_message_key: nil,
      quoted_external_message_key: nil,
      quoted_text: nil,
      quoted_sender_label: nil,
      quoted_attachment_refs: [],
      occurred_at: Time.current,
      transport_metadata: {},
      raw_payload: { "text" => text }
    )

    Class.new do
      define_method(:initialize) do |ingress_binding:, channel_connector:, envelope:|
        @ingress_binding = ingress_binding
        @channel_connector = channel_connector
        @envelope = envelope
      end

      define_method(:verify_request!) do |raw_payload:, request_metadata:|
        { ingress_binding: @ingress_binding, channel_connector: @channel_connector }
      end

      define_method(:normalize_envelope) do |raw_payload:, ingress_binding:, channel_connector:, request_metadata:|
        @envelope
      end
    end.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      envelope: envelope
    )
  end
end
