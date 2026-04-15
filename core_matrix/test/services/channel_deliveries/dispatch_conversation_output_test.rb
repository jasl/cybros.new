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

  test "orders published attachments with the primary deliverable first" do
    context = delivery_context
    output_message = attach_selected_output!(context[:turn], content: "Final answer with file")
    source_bundle = create_message_attachment!(
      message: output_message,
      filename: "source.zip",
      content_type: "application/zip",
      body: "source bundle"
    )
    primary = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "artifact body"
    )
    source_bundle.file.blob.update!(
      metadata: source_bundle.file.blob.metadata.merge("publication_role" => "source_bundle")
    )
    primary.file.blob.update!(
      metadata: primary.file.blob.metadata.merge("publication_role" => "primary_deliverable")
    )
    sender = FakeDeliverySender.new(deliveries: [])

    ChannelDeliveries::DispatchConversationOutput.call(
      conversation: context[:conversation],
      turn: context[:turn],
      message: output_message,
      delivery_sender: sender
    )

    delivery = sender.deliveries.last

    assert_equal primary.public_id, delivery.payload.dig("attachments", 0, "attachment_id")
    assert_equal "primary_deliverable", delivery.payload.dig("attachments", 0, "publication_role")
    assert_equal source_bundle.public_id, delivery.payload.dig("attachments", 1, "attachment_id")
  end

  test "routes weixin deliveries through the weixin reply sender" do
    context = delivery_context(platform: "weixin")
    weixin_deliveries = []
    telegram_deliveries = []
    original_weixin = ChannelDeliveries::SendWeixinReply.method(:call)
    original_telegram = ChannelDeliveries::SendTelegramReply.method(:call)
    ChannelDeliveries::SendWeixinReply.singleton_class.send(:define_method, :call) do |channel_delivery:|
      weixin_deliveries << channel_delivery
    end
    ChannelDeliveries::SendTelegramReply.singleton_class.send(:define_method, :call) do |channel_delivery:|
      telegram_deliveries << channel_delivery
    end

    ChannelDeliveries::DispatchConversationOutput.call(
      conversation: context[:conversation],
      channel_session: context[:channel_session],
      text: "Weixin final reply"
    )

    assert_equal 1, weixin_deliveries.length
    assert_empty telegram_deliveries
    assert_equal "Weixin final reply", weixin_deliveries.last.payload["text"]
  ensure
    ChannelDeliveries::SendWeixinReply.singleton_class.send(:define_method, :call, original_weixin)
    ChannelDeliveries::SendTelegramReply.singleton_class.send(:define_method, :call, original_telegram)
  end

  private

  def delivery_context(platform: "telegram")
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
      platform: platform,
      driver: platform == "telegram" ? "telegram_bot_api" : "claw_bot_sdk_weixin",
      transport_kind: platform == "telegram" ? "webhook" : "poller",
      label: "Primary #{platform.titleize}",
      lifecycle_state: "active",
      credential_ref_payload: platform == "telegram" ? {
        "bot_token" => "telegram-bot-token"
      } : {},
      config_payload: {},
      runtime_state_payload: platform == "weixin" ? {
        "base_url" => "https://weixin.example"
      } : {}
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: platform,
      peer_kind: "dm",
      peer_id: platform == "telegram" ? "telegram-user-1" : "weixin-user-1",
      thread_key: nil,
      session_metadata: platform == "telegram" ? {
        "telegram_preview_message_id" => 88,
        "telegram_preview_external_message_key" => "telegram:chat:telegram-user-1:message:88"
      } : {
        "context_token" => "ctx-1"
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
        "external_message_key" => "#{platform}:chat:#{channel_session.peer_id}:message:1001",
        "external_sender_id" => channel_session.peer_id,
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
