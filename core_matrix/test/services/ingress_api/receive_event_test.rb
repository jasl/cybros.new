require "test_helper"

class IngressAPI::ReceiveEventTest < ActiveSupport::TestCase
  test "runs middleware and preprocessors in the designed order" do
    context = ingress_runtime_context
    adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1001",
      external_message_key: "telegram:chat:1:message:1001",
      text: "hello from telegram"
    )

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
    ], result.trace
    assert_equal "ready_for_turn_entry", result.status
    assert_equal context[:channel_session], result.channel_session
    assert_equal context[:conversation], result.conversation
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
    context = ingress_runtime_context
    http_adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1003",
      external_message_key: "telegram:chat:1:message:1003",
      text: "from http"
    )
    runner_adapter = fake_adapter_for(
      context,
      external_event_key: "telegram:update:1004",
      external_message_key: "telegram:chat:1:message:1004",
      text: "from runner"
    )

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

    assert_equal "ready_for_turn_entry", http_result.status
    assert_equal "ready_for_turn_entry", runner_result.status
    assert_equal "http", http_result.request_metadata["source"]
    assert_equal "runner", runner_result.request_metadata["source"]
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

  def fake_adapter_for(context, external_event_key:, external_message_key:, text:)
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
