require "test_helper"

class ChannelInboundMessageTest < ActiveSupport::TestCase
  test "generates a public id and enforces one normalized inbound fact per external event key" do
    context = channel_message_context

    message = ChannelInboundMessage.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_event_key: "telegram:update:101",
      external_message_key: "telegram:chat:1:message:201",
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      content: { "text" => "hello from telegram" },
      normalized_payload: normalized_payload_for(context),
      raw_payload: { "update_id" => 101 },
      received_at: Time.current
    )

    duplicate = ChannelInboundMessage.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_event_key: "telegram:update:101",
      external_message_key: "telegram:chat:1:message:202",
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      content: { "text" => "duplicate update" },
      normalized_payload: normalized_payload_for(context),
      raw_payload: { "update_id" => 101 },
      received_at: Time.current
    )

    assert message.public_id.present?
    assert_equal message, ChannelInboundMessage.find_by_public_id!(message.public_id)
    assert_not duplicate.valid?
    assert duplicate.errors[:external_event_key].present? || duplicate.errors[:channel_connector_id].present? || duplicate.errors[:base].present?
  end

  test "rejects normalized payload references that expose internal bigint ids" do
    context = channel_message_context

    message = ChannelInboundMessage.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_event_key: "telegram:update:102",
      external_message_key: "telegram:chat:1:message:203",
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      content: { "text" => "hello from telegram" },
      normalized_payload: normalized_payload_for(context).merge(
        "conversation_id" => context[:conversation].id
      ),
      raw_payload: { "update_id" => 102 },
      received_at: Time.current
    )

    assert_not message.valid?
    assert_includes message.errors[:normalized_payload], "must use public ids for external resource references"
  end

  test "rejects optional normalized payload references when the referenced record is not attached" do
    context = channel_message_context

    message = ChannelInboundMessage.new(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: nil,
      external_event_key: "telegram:update:103",
      external_message_key: "telegram:chat:1:message:204",
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      content: { "text" => "hello from telegram" },
      normalized_payload: normalized_payload_for(context),
      raw_payload: { "update_id" => 103 },
      received_at: Time.current
    )

    assert_not message.valid?
    assert_includes message.errors[:normalized_payload], "must use public ids for external resource references"
  end

  private

  def channel_message_context
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

  def normalized_payload_for(context)
    {
      "ingress_binding_id" => context[:ingress_binding].public_id,
      "channel_connector_id" => context[:channel_connector].public_id,
      "channel_session_id" => context[:channel_session].public_id,
      "conversation_id" => context[:conversation].public_id,
    }
  end
end
