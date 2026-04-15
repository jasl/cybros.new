require "test_helper"

class IngressAPI::Preprocessors::MaterializeAttachmentsTest < ActiveSupport::TestCase
  test "downloads transport attachments into normalized attachment records" do
    context = attachment_context
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      envelope: IngressAPI::Envelope.new(
        platform: "telegram",
        driver: "telegram_bot_api",
        ingress_binding_public_id: context[:ingress_binding].public_id,
        channel_connector_public_id: context[:channel_connector].public_id,
        external_event_key: "telegram:update:#{next_test_sequence}",
        external_message_key: "telegram:chat:42:message:#{next_test_sequence}",
        peer_kind: "dm",
        peer_id: "42",
        thread_key: nil,
        external_sender_id: "telegram-user-1",
        sender_snapshot: { "label" => "Alice" },
        text: "User sent 1 attachment.",
        attachments: [
          {
            "file_id" => "document-1",
            "modality" => "file",
            "filename" => "notes.txt",
            "content_type" => "text/plain",
            "byte_size" => 12,
          },
        ],
        reply_to_external_message_key: nil,
        quoted_external_message_key: nil,
        quoted_text: nil,
        quoted_sender_label: nil,
        quoted_attachment_refs: [],
        occurred_at: Time.current,
        transport_metadata: {},
        raw_payload: {}
      ),
      pipeline_trace: []
    )
    original_call = IngressAPI::Telegram::DownloadAttachment.method(:call)
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call) do |**kwargs|
      {
        "file_id" => kwargs.fetch(:attachment_descriptor).fetch("file_id"),
        "filename" => "notes.txt",
        "content_type" => "text/plain",
        "byte_size" => 12,
        "modality" => "file",
        "io" => StringIO.new("hello world"),
        "transport_metadata" => { "file_path" => "documents/notes.txt" },
      }
    end

    IngressAPI::Preprocessors::MaterializeAttachments.call(context: ingress_context)

    assert_equal 1, ingress_context.attachment_records.length
    assert_equal "notes.txt", ingress_context.attachment_records.first.fetch("filename")
    assert_equal "file", ingress_context.attachment_records.first.fetch("modality")
    assert_equal "documents/notes.txt", ingress_context.attachment_records.first.dig("transport_metadata", "file_path")
  ensure
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call, original_call)
  end

  test "rejects inbound batches that exceed the configured attachment count limit before downloading" do
    context = attachment_context(
      config_payload: {
        "attachment_policy" => {
          "max_count" => 1,
        },
      }
    )
    ingress_context = build_ingress_context(
      context,
      attachments: [
        { "file_id" => "attachment-1", "modality" => "file", "filename" => "first.txt", "byte_size" => 12 },
        { "file_id" => "attachment-2", "modality" => "file", "filename" => "second.txt", "byte_size" => 12 },
      ]
    )
    original_call = IngressAPI::Telegram::DownloadAttachment.method(:call)
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call) do |**kwargs|
      raise "download should not be attempted when count exceeds the configured policy"
    end

    IngressAPI::Preprocessors::MaterializeAttachments.call(context: ingress_context)

    assert ingress_context.result.rejected?
    assert_equal "attachment_count_exceeded", ingress_context.result.rejection_reason
  ensure
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call, original_call)
  end

  test "rejects inbound attachments that exceed the configured size limit" do
    context = attachment_context(
      config_payload: {
        "attachment_policy" => {
          "max_bytes" => 8,
        },
      }
    )
    ingress_context = build_ingress_context(
      context,
      attachments: [
        { "file_id" => "attachment-1", "modality" => "file", "filename" => "oversize.txt", "byte_size" => 12 },
      ]
    )
    original_call = IngressAPI::Telegram::DownloadAttachment.method(:call)
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call) do |**kwargs|
      raise "download should not be attempted when byte size exceeds the configured policy"
    end

    IngressAPI::Preprocessors::MaterializeAttachments.call(context: ingress_context)

    assert ingress_context.result.rejected?
    assert_equal "attachment_too_large", ingress_context.result.rejection_reason
  ensure
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call, original_call)
  end

  private

  def attachment_context(config_payload: {})
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
        "bot_token" => "telegram-bot-token",
      },
      config_payload: config_payload,
      runtime_state_payload: {}
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
      conversation: conversation,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session
    )
  end

  def build_ingress_context(context, attachments:)
    IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      envelope: IngressAPI::Envelope.new(
        platform: "telegram",
        driver: "telegram_bot_api",
        ingress_binding_public_id: context[:ingress_binding].public_id,
        channel_connector_public_id: context[:channel_connector].public_id,
        external_event_key: "telegram:update:#{next_test_sequence}",
        external_message_key: "telegram:chat:42:message:#{next_test_sequence}",
        peer_kind: "dm",
        peer_id: "42",
        thread_key: nil,
        external_sender_id: "telegram-user-1",
        sender_snapshot: { "label" => "Alice" },
        text: "User sent #{attachments.length} attachment#{"s" if attachments.length != 1}.",
        attachments: attachments,
        reply_to_external_message_key: nil,
        quoted_external_message_key: nil,
        quoted_text: nil,
        quoted_sender_label: nil,
        quoted_attachment_refs: [],
        occurred_at: Time.current,
        transport_metadata: {},
        raw_payload: {}
      ),
      pipeline_trace: []
    )
  end
end
