require "test_helper"

class IngressAPI::Telegram::NormalizeUpdateTest < ActiveSupport::TestCase
  test "normalizes a text message update into the shared ingress envelope" do
    context = telegram_normalize_context

    envelope = IngressAPI::Telegram::NormalizeUpdate.call(
      update_payload: {
        "update_id" => 1001,
        "message" => {
          "message_id" => 55,
          "message_thread_id" => 9,
          "date" => 1_713_612_345,
          "chat" => { "id" => 42, "type" => "private" },
          "from" => { "id" => 7, "username" => "alice", "first_name" => "Alice" },
          "text" => "hello from telegram",
          "reply_to_message" => {
            "message_id" => 54,
            "text" => "older message",
          },
        },
      },
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector]
    )

    assert_equal "telegram", envelope.platform
    assert_equal "telegram_bot_api", envelope.driver
    assert_equal "telegram:update:1001", envelope.external_event_key
    assert_equal "telegram:chat:42:message:55", envelope.external_message_key
    assert_equal "dm", envelope.peer_kind
    assert_equal "42", envelope.peer_id
    assert_equal "9", envelope.thread_key
    assert_equal "7", envelope.external_sender_id
    assert_equal "hello from telegram", envelope.text
    assert_equal "telegram:chat:42:message:54", envelope.reply_to_external_message_key
    assert_empty envelope.attachments
  end

  test "normalizes media descriptors for photo and document messages" do
    context = telegram_normalize_context

    envelope = IngressAPI::Telegram::NormalizeUpdate.call(
      update_payload: {
        "update_id" => 1002,
        "message" => {
          "message_id" => 56,
          "date" => 1_713_612_346,
          "chat" => { "id" => -99, "type" => "supergroup" },
          "from" => { "id" => 8, "username" => "bob" },
          "caption" => "files attached",
          "photo" => [
            { "file_id" => "photo-small", "file_unique_id" => "photo-1", "file_size" => 10, "width" => 10, "height" => 10 },
            { "file_id" => "photo-large", "file_unique_id" => "photo-1", "file_size" => 20, "width" => 20, "height" => 20 },
          ],
          "document" => {
            "file_id" => "document-1",
            "file_unique_id" => "document-1",
            "file_name" => "notes.txt",
            "mime_type" => "text/plain",
            "file_size" => 12,
          },
        },
      },
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector]
    )

    assert_equal "group", envelope.peer_kind
    assert_equal "-99", envelope.peer_id
    assert_equal "files attached", envelope.text
    assert_equal 2, envelope.attachments.length
    assert_equal %w[image file], envelope.attachments.map { |attachment| attachment.fetch("modality") }
    assert_equal "photo-large", envelope.attachments.first.fetch("file_id")
    assert_equal "notes.txt", envelope.attachments.second.fetch("filename")
  end

  test "synthesizes transcript text for media only messages" do
    context = telegram_normalize_context

    envelope = IngressAPI::Telegram::NormalizeUpdate.call(
      update_payload: {
        "update_id" => 1003,
        "message" => {
          "message_id" => 57,
          "date" => 1_713_612_347,
          "chat" => { "id" => 42, "type" => "private" },
          "from" => { "id" => 7, "username" => "alice" },
          "document" => {
            "file_id" => "document-2",
            "file_unique_id" => "document-2",
            "file_name" => "notes.txt",
            "mime_type" => "text/plain",
            "file_size" => 12,
          },
        },
      },
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector]
    )

    assert_equal "User sent 1 attachment.", envelope.text
    assert_equal 1, envelope.attachments.length
    assert_equal "document-2", envelope.attachments.first.fetch("file_id")
  end

  private

  def telegram_normalize_context
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
        "bot_token" => "telegram-bot-token",
      },
      config_payload: {},
      runtime_state_payload: {}
    )

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector
    )
  end
end
