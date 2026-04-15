require "test_helper"

class ChannelDeliveries::SendTelegramReplyTest < ActiveSupport::TestCase
  BotSpy = Struct.new(:calls) do
    def send_message(**kwargs)
      calls << [:send_message, kwargs]
      { "message_id" => 201, "chat" => { "id" => kwargs.fetch(:chat_id) } }
    end

    def edit_message_text(**kwargs)
      calls << [:edit_message_text, kwargs]
      { "message_id" => kwargs.fetch(:message_id), "chat" => { "id" => kwargs.fetch(:chat_id) } }
    end

    def send_photo(**kwargs)
      calls << [:send_photo, kwargs.except(:photo)]
      { "message_id" => 202, "chat" => { "id" => kwargs.fetch(:chat_id) } }
    end

    def send_document(**kwargs)
      calls << [:send_document, kwargs.except(:document)]
      { "message_id" => 203, "chat" => { "id" => kwargs.fetch(:chat_id) } }
    end
  end

  test "sends final text replies with send_message and stamps the delivery as delivered" do
    context = telegram_delivery_context
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    delivery = create_channel_delivery!(
      context,
      payload: {
        "text" => "final reply"
      }
    )

    ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)

    assert_equal [[:send_message, { chat_id: 42, text: "final reply" }]], bot.calls
    assert_equal "delivered", delivery.reload.delivery_state
    assert_equal "telegram:chat:42:message:201", delivery.external_message_key
  end

  test "uses edit_message_text for preview updates when a preview message id is supplied" do
    context = telegram_delivery_context
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    delivery = create_channel_delivery!(
      context,
      external_message_key: "telegram:chat:42:message:155",
      payload: {
        "delivery_mode" => "preview_stream",
        "preview_message_id" => 155,
        "text" => "updated preview"
      }
    )

    ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)

    assert_equal [[:edit_message_text, { chat_id: 42, message_id: 155, text: "updated preview" }]], bot.calls
    assert_equal "delivered", delivery.reload.delivery_state
  end

  test "sends image and file attachments through the native telegram methods" do
    context = telegram_delivery_context
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    image = Tempfile.new(["telegram-image", ".jpg"])
    image.write("image-bytes")
    image.rewind
    document = Tempfile.new(["telegram-document", ".txt"])
    document.write("document-bytes")
    document.rewind
    delivery = create_channel_delivery!(
      context,
      payload: {
        "attachments" => [
          {
            "modality" => "image",
            "path" => image.path,
            "filename" => "preview.jpg"
          },
          {
            "modality" => "file",
            "path" => document.path,
            "filename" => "notes.txt"
          }
        ]
      }
    )

    ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)

    assert_equal :send_photo, bot.calls.first.first
    assert_equal({ chat_id: 42, caption: nil }, bot.calls.first.last)
    assert_equal :send_document, bot.calls.second.first
    assert_equal({ chat_id: 42, caption: nil }, bot.calls.second.last)
  ensure
    image&.close!
    document&.close!
  end

  test "reopens stored transcript attachments by public id for telegram delivery" do
    context = telegram_delivery_context
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    output_message = attach_selected_output!(create_turn_with_input!(context[:conversation]), content: "artifact delivery")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "artifact body"
    )
    delivery = create_channel_delivery!(
      context,
      message: output_message,
      payload: {
        "attachments" => [
          {
            "attachment_id" => attachment.public_id,
            "filename" => "artifact.txt",
            "modality" => "file"
          }
        ]
      }
    )

    ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)

    assert_equal [[:send_document, { chat_id: 42, caption: nil }]], bot.calls
  end

  test "final preview deliveries still send attachments after updating the preview text" do
    context = telegram_delivery_context
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    output_message = attach_selected_output!(create_turn_with_input!(context[:conversation]), content: "final answer")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "artifact body"
    )
    delivery = create_channel_delivery!(
      context,
      message: output_message,
      payload: {
        "delivery_mode" => "preview_stream",
        "preview_message_id" => 155,
        "text" => "final answer",
        "attachments" => [
          {
            "attachment_id" => attachment.public_id,
            "filename" => "artifact.txt",
            "modality" => "file"
          }
        ]
      }
    )

    ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)

    assert_equal [:edit_message_text, :send_document], bot.calls.map(&:first)
    assert_equal({ chat_id: 42, message_id: 155, text: "final answer" }, bot.calls.first.last)
    assert_equal({ chat_id: 42, caption: nil }, bot.calls.second.last)
  end

  test "records already-delivered telegram message keys when a later attachment send fails" do
    context = telegram_delivery_context
    attachment = create_message_attachment!(
      message: attach_selected_output!(create_turn_with_input!(context[:conversation]), content: "artifact delivery"),
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "artifact body"
    )
    second_attachment = create_message_attachment!(
      message: attachment.message,
      filename: "second.txt",
      content_type: "text/plain",
      body: "second body"
    )
    bot = Object.new
    calls = []
    bot.define_singleton_method(:send_document) do |**kwargs|
      calls << kwargs.except(:document)
      if calls.length == 1
        { "message_id" => 301, "chat" => { "id" => kwargs.fetch(:chat_id) } }
      else
        raise "telegram send failed"
      end
    end
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    delivery = create_channel_delivery!(
      context,
      payload: {
        "attachments" => [
          { "attachment_id" => attachment.public_id, "filename" => "artifact.txt", "modality" => "file" },
          { "attachment_id" => second_attachment.public_id, "filename" => "second.txt", "modality" => "file" }
        ]
      }
    )

    error = assert_raises(RuntimeError) do
      ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)
    end

    assert_equal "telegram send failed", error.message
    assert_equal "failed", delivery.reload.delivery_state
    assert_equal ["telegram:chat:42:message:301"], delivery.failure_payload["delivered_external_message_keys"]
  end

  test "falls back to a signed download link for non-image transcript attachments at or above one megabyte" do
    context = telegram_delivery_context
    bot = BotSpy.new([])
    client = IngressAPI::Telegram::Client.new(bot_token: "telegram-bot-token", bot: bot)
    output_message = attach_selected_output!(create_turn_with_input!(context[:conversation]), content: "artifact delivery")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "a" * (1.megabyte + 1)
    )
    delivery = create_channel_delivery!(
      context,
      message: output_message,
      payload: {
        "text" => "artifact delivery",
        "attachments" => [
          {
            "attachment_id" => attachment.public_id,
            "filename" => "artifact.txt",
            "modality" => "file"
          }
        ]
      }
    )

    ChannelDeliveries::SendTelegramReply.call(channel_delivery: delivery, client: client)

    assert_equal [[:send_message, bot.calls.first.last]], bot.calls
    assert_includes bot.calls.first.last.fetch(:text), "artifact.txt"
    assert_match %r{https?://example.com/rails/active_storage/blobs/redirect/}, bot.calls.first.last.fetch(:text)
  end

  private

  def telegram_delivery_context
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
      peer_id: "42",
      thread_key: nil,
      session_metadata: {}
    )

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      conversation: conversation
    )
  end

  def create_channel_delivery!(context, **attrs)
    ChannelDelivery.create!({
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_message_key: "telegram:chat:42:message:200",
      payload: {},
      failure_payload: {}
    }.merge(attrs))
  end

  def create_turn_with_input!(conversation)
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
  end
end
