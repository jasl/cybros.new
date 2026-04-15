require "test_helper"

class IngressAPI::Preprocessors::AuthorizeAndPairTest < ActiveSupport::TestCase
  test "creates a pending pairing request for an unknown dm sender and stops processing" do
    context = telegram_pairing_context
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      envelope: dm_envelope(context, sender_id: "telegram-user-1", text: "hello from telegram"),
      request_metadata: { "source" => "test" },
      pipeline_trace: []
    )

    assert_difference("ChannelPairingRequest.count", 1) do
      IngressAPI::Preprocessors::AuthorizeAndPair.call(context: ingress_context)
    end

    pairing_request = ChannelPairingRequest.order(:id).last

    assert_predicate ingress_context.result, :handled?
    assert_equal "pairing_required", ingress_context.result.handled_via
    assert_equal pairing_request.public_id, ingress_context.result.payload["pairing_request_id"]
    assert_equal "pending", pairing_request.lifecycle_state
    assert_equal "telegram-user-1", pairing_request.platform_sender_id
    assert_equal({ "label" => "Alice" }, pairing_request.sender_snapshot)
  end

  test "creates an active dm session for an approved sender and lets processing continue" do
    context = telegram_pairing_context
    pairing_request = ChannelPairingRequest.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "approved",
      approved_at: Time.current,
      expires_at: 30.minutes.from_now
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      envelope: dm_envelope(context, sender_id: "telegram-user-1", text: "approved sender"),
      request_metadata: { "source" => "test" },
      pipeline_trace: []
    )

    assert_difference("ChannelSession.count", 1) do
      IngressAPI::Preprocessors::AuthorizeAndPair.call(context: ingress_context)
    end

    session = ingress_context.channel_session

    assert_nil ingress_context.result
    assert_predicate session, :present?
    assert_equal pairing_request.reload.channel_session, session
    assert_equal "active", session.binding_state
    assert_equal "dm", session.peer_kind
    assert_equal "telegram-user-1", session.peer_id
    assert_equal context[:workspace_agent], session.conversation.workspace_agent
    assert_equal context[:execution_runtime], session.conversation.current_execution_runtime
  end

  test "rolls back the root conversation if dm session creation fails" do
    context = telegram_pairing_context
    ChannelPairingRequest.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "telegram-user-1",
      sender_snapshot: { "label" => "Alice" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "approved",
      approved_at: Time.current,
      expires_at: 30.minutes.from_now
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      envelope: dm_envelope(context, sender_id: "telegram-user-1", text: "approved sender"),
      request_metadata: { "source" => "test" },
      pipeline_trace: []
    )
    original_create = ChannelSession.method(:create!)
    ChannelSession.singleton_class.send(:define_method, :create!) do |*args, **kwargs|
      raise ActiveRecord::RecordInvalid.new(ChannelSession.new)
    end

    assert_no_difference("Conversation.count") do
      assert_raises(ActiveRecord::RecordInvalid) do
        IngressAPI::Preprocessors::AuthorizeAndPair.call(context: ingress_context)
      end
    end
  ensure
    ChannelSession.singleton_class.send(:define_method, :create!, original_create)
  end

  private

  def telegram_pairing_context
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

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector
    )
  end

  def dm_envelope(context, sender_id:, text:)
    IngressAPI::Envelope.new(
      platform: "telegram",
      driver: "telegram_bot_api",
      ingress_binding_public_id: context[:ingress_binding].public_id,
      channel_connector_public_id: context[:channel_connector].public_id,
      external_event_key: "telegram:update:#{next_test_sequence}",
      external_message_key: "telegram:chat:telegram-user-1:message:#{next_test_sequence}",
      peer_kind: "dm",
      peer_id: sender_id,
      thread_key: nil,
      external_sender_id: sender_id,
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
  end
end
