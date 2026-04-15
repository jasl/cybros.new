require "test_helper"

class IngressAPI::ReceiveEventTest < ActiveSupport::TestCase
  test "runs middleware and preprocessors in the designed order and materializes transcript entry" do
    context = ingress_runtime_context
    adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1001",
      external_message_key: "telegram:chat:1:message:1001",
      text: "hello from telegram"
    )

    assert_difference("Turn.count", 1) do
      result = IngressAPI::ReceiveEvent.call(
        adapter: adapter,
        raw_payload: { "update_id" => 1001 },
        request_metadata: { "source" => "http" }
      )

      assert_equal %w[
        capture_raw_payload
        verify_request
        adapter_normalize_envelope
        deduplicate_inbound
        resolve_channel_session
        authorize_and_pair
        create_or_bind_conversation
        dispatch_command
        coalesce_burst
        materialize_attachments
        resolve_dispatch_decision
        materialize_turn_entry
      ], result.trace
      assert result.handled?
      assert_equal "transcript_entry", result.handled_via
      assert_equal context[:channel_session], result.channel_session
      assert_equal context[:conversation], result.conversation
    end

    assert_equal "hello from telegram", context[:conversation].reload.latest_turn.selected_input_message.content
  end

  test "ignores duplicate external event keys idempotently" do
    context = ingress_runtime_context
    ChannelInboundMessage.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_event_key: "telegram:update:1002",
      external_message_key: "telegram:chat:1:message:1002",
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      content: { "text" => "duplicate" },
      normalized_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => context[:channel_session].public_id,
        "conversation_id" => context[:conversation].public_id,
      },
      raw_payload: { "update_id" => 1002 },
      received_at: Time.current
    )
    adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1002",
      external_message_key: "telegram:chat:1:message:1002",
      text: "duplicate"
    )

    result = IngressAPI::ReceiveEvent.call(
      adapter: adapter,
      raw_payload: { "update_id" => 1002 },
      request_metadata: { "source" => "http" }
    )

    assert result.duplicate?
    assert_equal %w[capture_raw_payload verify_request adapter_normalize_envelope deduplicate_inbound], result.trace
  end

  test "can be called from either an http controller or a connector runner" do
    http_context = ingress_runtime_context
    runner_context = ingress_runtime_context
    http_adapter = fake_adapter_for(
      http_context,
      external_event_key: "telegram:update:1003",
      external_message_key: "telegram:chat:1:message:1003",
      text: "from http"
    )
    runner_adapter = fake_adapter_for(
      runner_context,
      external_event_key: "telegram:update:1004",
      external_message_key: "telegram:chat:1:message:1004",
      text: "from runner"
    )

    assert_difference("Turn.count", 2) do
      http_result = IngressAPI::ReceiveEvent.call(
        adapter: http_adapter,
        raw_payload: { "update_id" => 1003 },
        request_metadata: { "source" => "http" }
      )
      runner_result = IngressAPI::ReceiveEvent.call(
        adapter: runner_adapter,
        raw_payload: { "update_id" => 1004 },
        request_metadata: { "source" => "runner" }
      )

      assert_equal "handled", http_result.status
      assert_equal "handled", runner_result.status
      assert_equal "http", http_result.request_metadata["source"]
      assert_equal "runner", runner_result.request_metadata["source"]
    end
  end

  test "materializes inbound attachments onto the transcript input message" do
    context = ingress_runtime_context
    adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1005",
      external_message_key: "telegram:chat:1:message:1005",
      text: "User sent 1 attachment.",
      attachments: [
        {
          "file_id" => "document-1",
          "modality" => "file",
          "filename" => "notes.txt",
          "content_type" => "text/plain",
          "byte_size" => 12,
        },
      ]
    )
    original_call = IngressAPI::Telegram::DownloadAttachment.method(:call)
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call) do |**kwargs|
      {
        "file_id" => kwargs.fetch(:attachment_descriptor).fetch("file_id"),
        "filename" => "notes.txt",
        "content_type" => "text/plain",
        "byte_size" => 12,
        "modality" => "file",
        "io" => StringIO.new("attachment body"),
        "transport_metadata" => { "file_path" => "telegram/path/notes.txt" },
      }
    end

    IngressAPI::ReceiveEvent.call(
      adapter: adapter,
      raw_payload: { "update_id" => 1005 },
      request_metadata: { "source" => "http" }
    )

    input_message = context[:conversation].reload.latest_turn.selected_input_message
    assert_equal 1, input_message.message_attachments.count
    assert_equal "notes.txt", input_message.message_attachments.first.file.blob.filename.to_s
    assert_equal "document-1", input_message.message_attachments.first.file.blob.metadata["source_file_id"]
    assert_equal({ "file_path" => "telegram/path/notes.txt" }, input_message.message_attachments.first.file.blob.metadata["transport_metadata"])
  ensure
    IngressAPI::Telegram::DownloadAttachment.singleton_class.send(:define_method, :call, original_call)
  end

  test "persists quoted context on the inbound fact and materialized turn origin payload" do
    context = ingress_runtime_context
    adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1006",
      external_message_key: "telegram:chat:1:message:1006",
      text: "reply with quote",
      reply_to_external_message_key: "telegram:chat:1:message:1005",
      quoted_external_message_key: "telegram:chat:1:message:1005",
      quoted_text: "Earlier targeted message",
      quoted_sender_label: "Bob",
      quoted_attachment_refs: [
        {
          "modality" => "file",
          "filename" => "notes.txt",
        },
      ]
    )

    IngressAPI::ReceiveEvent.call(
      adapter: adapter,
      raw_payload: { "update_id" => 1006 },
      request_metadata: { "source" => "http" }
    )

    inbound_message = ChannelInboundMessage.order(:id).last
    turn = context[:conversation].reload.latest_turn

    assert_equal "telegram:chat:1:message:1005", inbound_message.normalized_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:1:message:1005", inbound_message.normalized_payload["quoted_external_message_key"]
    assert_equal "Earlier targeted message", inbound_message.normalized_payload["quoted_text"]
    assert_equal "Bob", inbound_message.normalized_payload["quoted_sender_label"]
    assert_equal [{ "modality" => "file", "filename" => "notes.txt" }], inbound_message.normalized_payload["quoted_attachment_refs"]

    assert_equal "telegram:chat:1:message:1005", turn.origin_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:1:message:1005", turn.origin_payload["quoted_external_message_key"]
    assert_equal "Earlier targeted message", turn.origin_payload["quoted_text"]
    assert_equal "Bob", turn.origin_payload["quoted_sender_label"]
    assert_equal [{ "modality" => "file", "filename" => "notes.txt" }], turn.origin_payload["quoted_attachment_refs"]
  end

  private

  def ingress_runtime_context
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

  def fake_adapter_for(
    context,
    external_event_key:,
    external_message_key:,
    text:,
    attachments: [],
    reply_to_external_message_key: nil,
    quoted_external_message_key: nil,
    quoted_text: nil,
    quoted_sender_label: nil,
    quoted_attachment_refs: []
  )
    envelope = IngressAPI::Envelope.new(
      platform: "telegram",
      driver: "telegram_bot_api",
      ingress_binding_public_id: context[:ingress_binding].public_id,
      channel_connector_public_id: context[:channel_connector].public_id,
      external_event_key: external_event_key,
      external_message_key: external_message_key,
      peer_kind: "dm",
      peer_id: "telegram-user-1",
      thread_key: nil,
      external_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      text: text,
      attachments: attachments,
      reply_to_external_message_key: reply_to_external_message_key,
      quoted_external_message_key: quoted_external_message_key,
      quoted_text: quoted_text,
      quoted_sender_label: quoted_sender_label,
      quoted_attachment_refs: quoted_attachment_refs,
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
