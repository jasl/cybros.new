require "test_helper"

class IngressApiTelegramUpdatesControllerTest < ActionDispatch::IntegrationTest
  test "accepts a verified webhook update and passes it into ReceiveEvent" do
    context = telegram_ingress_context
    received = nil
    original_call = IngressAPI::ReceiveEvent.method(:call)
    IngressAPI::ReceiveEvent.singleton_class.send(:define_method, :call) do |**kwargs|
      received = kwargs
      IngressAPI::Result.ready_for_turn_entry(
        trace: ["verify_request", "adapter_normalize_envelope"],
        envelope: nil,
        conversation: nil,
        channel_session: nil,
        request_metadata: kwargs.fetch(:request_metadata)
      )
    end

    post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
      params: {
        update_id: 101,
        message: {
          message_id: 55,
          date: 1_713_612_345,
          chat: { id: 42, type: "private" },
          from: { id: 7, username: "alice" },
          text: "hello"
        }
      },
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret]
      },
      as: :json

    assert_response :ok
    assert_equal "ready_for_turn_entry", response.parsed_body.fetch("status")
    assert_equal "telegram_webhook", received.fetch(:request_metadata).fetch("source")
    assert_equal 101, received.fetch(:raw_payload).fetch("update_id")
    assert received.fetch(:adapter).respond_to?(:verify_request!)
    assert received.fetch(:adapter).respond_to?(:normalize_envelope)
  ensure
    IngressAPI::ReceiveEvent.singleton_class.send(:define_method, :call, original_call)
  end

  test "rejects webhook requests with an invalid secret token" do
    context = telegram_ingress_context

    post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
      params: { update_id: 102 },
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => "wrong-secret"
      },
      as: :json

    assert_response :unauthorized
  end

  test "processes a verified webhook update end to end into transcript entry" do
    context = telegram_ingress_context
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: conversation,
      platform: "telegram",
      peer_kind: "dm",
      peer_id: "42",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {}
    )

    assert_difference(["ChannelInboundMessage.count", "Turn.count", "Message.count"], 1) do
      post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
        params: {
          update_id: 103,
          message: {
            message_id: 56,
            date: 1_713_612_346,
            chat: { id: 42, type: "private" },
            from: { id: 42, username: "alice" },
            text: "hello end to end"
          }
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret]
        },
        as: :json
    end

    assert_response :ok
    assert_equal "handled", response.parsed_body.fetch("status")
    assert_equal "transcript_entry", response.parsed_body.fetch("handled_via")

    turn = conversation.reload.latest_turn
    assert_equal "channel_ingress", turn.origin_kind
    assert_equal "ChannelInboundMessage", turn.source_ref_type
    assert_equal "hello end to end", turn.selected_input_message.content
  end

  test "creates a pending pairing request for an unknown dm sender over the real webhook path" do
    context = telegram_ingress_context

    assert_difference("ChannelPairingRequest.count", 1) do
      assert_no_difference(["Turn.count", "ChannelInboundMessage.count"]) do
        post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
          params: {
            update_id: 104,
            message: {
              message_id: 57,
              date: 1_713_612_347,
              chat: { id: 77, type: "private" },
              from: { id: 77, username: "new_user" },
              text: "hello first contact"
            }
          },
          headers: {
            "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret]
          },
          as: :json
      end
    end

    assert_response :ok
    assert_equal "handled", response.parsed_body.fetch("status")
    assert_equal "pairing_required", response.parsed_body.fetch("handled_via")
  end

  test "creates a new dm session from an approved pairing request over the real webhook path" do
    context = telegram_ingress_context
    ChannelPairingRequest.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      platform_sender_id: "88",
      sender_snapshot: { "username" => "approved_user" },
      pairing_code_digest: Digest::SHA256.hexdigest(unique_test_token("pairing-code")),
      lifecycle_state: "approved",
      approved_at: Time.current,
      expires_at: 30.minutes.from_now
    )

    assert_difference(["ChannelSession.count", "Turn.count", "Message.count", "ChannelInboundMessage.count"], 1) do
      post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
        params: {
          update_id: 105,
          message: {
            message_id: 58,
            date: 1_713_612_348,
            chat: { id: 88, type: "private" },
            from: { id: 88, username: "approved_user" },
            text: "hello approved first contact"
          }
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret]
        },
        as: :json
    end

    assert_response :ok
    assert_equal "handled", response.parsed_body.fetch("status")
    assert_equal "transcript_entry", response.parsed_body.fetch("handled_via")
    assert_equal "88", ChannelSession.order(:id).last.peer_id
  end

  private

  def telegram_ingress_context
    context = create_workspace_context!
    plaintext_secret, secret_digest = IngressBinding.issue_ingress_secret
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      ingress_secret_digest: secret_digest,
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
      plaintext_secret: plaintext_secret,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector
    )
  end
end
