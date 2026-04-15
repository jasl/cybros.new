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
          text: "hello",
        },
      },
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
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
        "X-Telegram-Bot-Api-Secret-Token" => "wrong-secret",
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
    channel_session = ChannelSession.create!(
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
            text: "hello end to end",
          },
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
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
              text: "hello first contact",
            },
          },
          headers: {
            "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
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
            text: "hello approved first contact",
          },
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
        },
        as: :json
    end

    assert_response :ok
    assert_equal "handled", response.parsed_body.fetch("status")
    assert_equal "transcript_entry", response.parsed_body.fetch("handled_via")
    assert_equal "88", ChannelSession.order(:id).last.peer_id
  end

  test "propagates reply quote explicit context through the real webhook path" do
    context = telegram_ingress_context
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    channel_session = ChannelSession.create!(
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

    post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
      params: {
        update_id: 106,
        message: {
          message_id: 59,
          date: 1_713_612_349,
          chat: { id: 42, type: "private" },
          from: { id: 42, username: "alice" },
          text: "reply with quote",
          reply_to_message: {
            message_id: 58,
            from: { id: 7, first_name: "Bob", last_name: "Builder" },
            caption: "quoted photo",
            photo: [
              { file_id: "photo-small", file_unique_id: "photo-1", file_size: 10, width: 10, height: 10 },
              { file_id: "photo-large", file_unique_id: "photo-1", file_size: 20, width: 20, height: 20 },
            ],
          },
        },
      },
      headers: {
        "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
      },
      as: :json

    assert_response :ok

    inbound_message = ChannelInboundMessage.order(:id).last
    turn = conversation.reload.latest_turn

    assert_equal "telegram:chat:42:message:58", inbound_message.normalized_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:42:message:58", inbound_message.normalized_payload["quoted_external_message_key"]
    assert_equal "quoted photo", inbound_message.normalized_payload["quoted_text"]
    assert_equal "Bob Builder", inbound_message.normalized_payload["quoted_sender_label"]
    assert_equal [{"file_id" => "photo-large", "file_unique_id" => "photo-1", "modality" => "image", "byte_size" => 20, "width" => 20, "height" => 20}], inbound_message.normalized_payload["quoted_attachment_refs"]

    assert_equal "telegram:chat:42:message:58", turn.origin_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:42:message:58", turn.origin_payload["quoted_external_message_key"]
    assert_equal "quoted photo", turn.origin_payload["quoted_text"]
    assert_equal "Bob Builder", turn.origin_payload["quoted_sender_label"]
    assert_equal [{"file_id" => "photo-large", "file_unique_id" => "photo-1", "modality" => "image", "byte_size" => 20, "width" => 20, "height" => 20}], turn.origin_payload["quoted_attachment_refs"]
  end

  test "preserves quoted metadata when the real webhook path steers the active shared-channel turn" do
    context = telegram_ingress_context
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: conversation,
      platform: "telegram",
      peer_kind: "group",
      peer_id: "-99",
      thread_key: "1",
      binding_state: "active",
      session_metadata: {}
    )
    active_turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: Struct.new(:public_id).new("seed-inbound"),
      content: "original group input",
      origin_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => channel_session.public_id,
        "external_sender_id" => "7",
        "external_message_key" => "telegram:chat:-99:message:40",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.4"
    )

    assert_no_difference("Turn.count") do
      assert_difference(["ChannelInboundMessage.count", "Message.count"], 1) do
        post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
          params: {
            update_id: 107,
            message: {
              message_id: 60,
              message_thread_id: 1,
              date: 1_713_612_350,
              chat: { id: -99, type: "supergroup" },
              from: { id: 7, username: "alice" },
              text: "shared-channel steer with quote",
              reply_to_message: {
                message_id: 59,
                from: { id: 8, first_name: "Bob" },
                text: "targeted group quote",
                photo: [
                  { file_id: "photo-small", file_unique_id: "photo-1", file_size: 10, width: 10, height: 10 },
                  { file_id: "photo-large", file_unique_id: "photo-1", file_size: 20, width: 20, height: 20 },
                ],
              },
            },
          },
          headers: {
            "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
          },
          as: :json
      end
    end

    assert_response :ok
    turn = active_turn.reload
    inbound_message = ChannelInboundMessage.order(:id).last

    assert_equal inbound_message.public_id, turn.source_ref_id
    assert_includes turn.selected_input_message.content, "shared-channel steer with quote"
    assert_equal "telegram:chat:-99:message:59", turn.origin_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:-99:message:59", turn.origin_payload["quoted_external_message_key"]
    assert_equal "targeted group quote", turn.origin_payload["quoted_text"]
    assert_equal "Bob", turn.origin_payload["quoted_sender_label"]
    assert_equal [{"file_id" => "photo-large", "file_unique_id" => "photo-1", "modality" => "image", "byte_size" => 20, "width" => 20, "height" => 20}], turn.origin_payload["quoted_attachment_refs"]
  end

  test "preserves quoted metadata when the real webhook path queues shared-channel follow-up work" do
    context = telegram_ingress_context
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime]
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      conversation: conversation,
      platform: "telegram",
      peer_kind: "group",
      peer_id: "-99",
      thread_key: "1",
      binding_state: "active",
      session_metadata: {}
    )
    active_turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: Struct.new(:public_id).new("seed-inbound"),
      content: "original group input",
      origin_payload: {
        "ingress_binding_id" => context[:ingress_binding].public_id,
        "channel_connector_id" => context[:channel_connector].public_id,
        "channel_session_id" => channel_session.public_id,
        "external_sender_id" => "7",
        "external_message_key" => "telegram:chat:-99:message:40",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.4"
    )
    create_workflow_run!(turn: active_turn)
    attach_selected_output!(active_turn, content: "side effect crossed")

    assert_difference(["Turn.count", "ChannelInboundMessage.count", "Message.count"], 1) do
      post "/ingress_api/telegram/bindings/#{context[:ingress_binding].public_ingress_id}/updates",
        params: {
          update_id: 108,
          message: {
            message_id: 61,
            message_thread_id: 1,
            date: 1_713_612_351,
            chat: { id: -99, type: "supergroup" },
            from: { id: 7, username: "alice" },
            text: "shared-channel queued follow up with quote",
            reply_to_message: {
              message_id: 60,
              from: { id: 8, first_name: "Bob" },
              text: "queued targeted quote",
              document: {
                file_id: "document-1",
                file_unique_id: "document-1",
                file_name: "notes.txt",
                mime_type: "text/plain",
                file_size: 12,
              },
            },
          },
        },
        headers: {
          "X-Telegram-Bot-Api-Secret-Token" => context[:plaintext_secret],
        },
        as: :json
    end

    assert_response :ok
    queued_turn = conversation.reload.turns.order(:sequence).last
    inbound_message = ChannelInboundMessage.order(:id).last

    assert_predicate queued_turn, :queued?
    assert_equal "channel_ingress", queued_turn.origin_kind
    assert_equal inbound_message.public_id, queued_turn.source_ref_id
    assert_equal "telegram:chat:-99:message:60", queued_turn.origin_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:-99:message:60", queued_turn.origin_payload["quoted_external_message_key"]
    assert_equal "queued targeted quote", queued_turn.origin_payload["quoted_text"]
    assert_equal "Bob", queued_turn.origin_payload["quoted_sender_label"]
    assert_equal [{"file_id" => "document-1", "file_unique_id" => "document-1", "modality" => "file", "filename" => "notes.txt", "content_type" => "text/plain", "byte_size" => 12}], queued_turn.origin_payload["quoted_attachment_refs"]
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
        "bot_token" => "telegram-bot-token",
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
