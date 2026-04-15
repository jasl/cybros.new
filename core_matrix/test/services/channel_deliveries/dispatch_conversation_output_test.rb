require "test_helper"

class ChannelDeliveries::DispatchConversationOutputTest < ActiveSupport::TestCase
  FakeDeliverySender = Struct.new(:deliveries, keyword_init: true) do
    def call(channel_delivery:)
      deliveries << channel_delivery
    end
  end

  test "creates a final delivery that reuses the editable preview message when present" do
    context = delivery_context
    output_message = attach_selected_output!(context[:turn], content: "Final answer")
    sender = FakeDeliverySender.new(deliveries: [])

    ChannelDeliveries::DispatchConversationOutput.call(
      conversation: context[:conversation],
      turn: context[:turn],
      message: output_message,
      delivery_sender: sender
    )

    delivery = sender.deliveries.last

    assert_predicate delivery, :present?
    assert_equal "preview_stream", delivery.payload["delivery_mode"]
    assert_equal 88, delivery.payload["preview_message_id"]
    assert_equal "Final answer", delivery.payload["text"]
    assert_equal "telegram:chat:telegram-user-1:message:1001", delivery.reply_to_external_message_key
  end

  test "projects output attachments as native delivery attachments" do
    context = delivery_context
    output_message = attach_selected_output!(context[:turn], content: "Final answer with file")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "artifact body"
    )
    sender = FakeDeliverySender.new(deliveries: [])

    ChannelDeliveries::DispatchConversationOutput.call(
      conversation: context[:conversation],
      turn: context[:turn],
      message: output_message,
      delivery_sender: sender
    )

    delivery = sender.deliveries.last

    assert_equal 1, delivery.payload.fetch("attachments").length
    assert_equal attachment.public_id, delivery.payload.dig("attachments", 0, "attachment_id")
    assert_equal "artifact.txt", delivery.payload.dig("attachments", 0, "filename")
  end

  private

  def delivery_context
    context = create_workspace_context!
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
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
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      session_metadata: {
        "telegram_preview_message_id" => 88,
        "telegram_preview_external_message_key" => "telegram:chat:telegram-user-1:message:88"
      }
    )
    turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: Struct.new(:public_id).new("channel-inbound-1"),
      content: "Original inbound input",
      origin_payload: {
        "ingress_binding_id" => ingress_binding.public_id,
        "channel_connector_id" => channel_connector.public_id,
        "channel_session_id" => channel_session.public_id,
        "external_message_key" => "telegram:chat:telegram-user-1:message:1001",
        "external_sender_id" => "telegram-user-1",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    context.merge(
      conversation: conversation,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      turn: turn
    )
  end
end
