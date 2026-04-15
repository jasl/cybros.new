require "test_helper"

class IngressAPI::Preprocessors::ResolveDispatchDecisionTest < ActiveSupport::TestCase
  test "chooses new turn when no work is active" do
    context = dispatch_context
    ingress_context = build_ingress_context(context, sender_id: "telegram-user-1", text: "New work")

    IngressAPI::Preprocessors::ResolveDispatchDecision.call(context: ingress_context)

    assert_equal "new_turn", ingress_context.dispatch_decision
    assert_equal ["channel-inbound-1"], ingress_context.origin_payload["merged_inbound_message_ids"]
  end

  test "chooses steer for same sender input before the transcript side effect boundary" do
    context = dispatch_context
    active_turn = create_channel_turn!(
      context,
      sender_id: "telegram-user-1",
      content: "Original input"
    )
    ingress_context = build_ingress_context(
      context,
      sender_id: "telegram-user-1",
      text: "Follow up",
      active_turn: active_turn
    )

    IngressAPI::Preprocessors::ResolveDispatchDecision.call(context: ingress_context)

    assert_equal "steer_current_turn", ingress_context.dispatch_decision
  end

  test "chooses queue after the first transcript side effect boundary" do
    context = dispatch_context
    active_turn = create_channel_turn!(
      context,
      sender_id: "telegram-user-1",
      content: "Original input"
    )
    attach_selected_output!(active_turn, content: "Streaming output")
    ingress_context = build_ingress_context(
      context,
      sender_id: "telegram-user-1",
      text: "Queued follow up",
      active_turn: active_turn.reload
    )

    IngressAPI::Preprocessors::ResolveDispatchDecision.call(context: ingress_context)

    assert_equal "queue_follow_up", ingress_context.dispatch_decision
  end

  test "queues cross sender input in a shared conversation even before side effects" do
    context = dispatch_context
    active_turn = create_channel_turn!(
      context,
      sender_id: "telegram-user-1",
      content: "Original input"
    )
    ingress_context = build_ingress_context(
      context,
      sender_id: "telegram-user-2",
      text: "Other sender follow up",
      active_turn: active_turn
    )

    IngressAPI::Preprocessors::ResolveDispatchDecision.call(context: ingress_context)

    assert_equal "queue_follow_up", ingress_context.dispatch_decision
  end

  test "carries explicit quoted context into origin payload for downstream execution context" do
    context = dispatch_context
    ingress_context = build_ingress_context(
      context,
      sender_id: "telegram-user-1",
      text: "Quoted follow up",
      reply_to_external_message_key: "telegram:chat:telegram-group-1:message:41",
      quoted_external_message_key: "telegram:chat:telegram-group-1:message:41",
      quoted_text: "Earlier targeted message",
      quoted_sender_label: "Bob",
      quoted_attachment_refs: [
        {
          "modality" => "image",
          "file_id" => "photo-1",
        },
      ]
    )

    IngressAPI::Preprocessors::ResolveDispatchDecision.call(context: ingress_context)

    assert_equal "telegram:chat:telegram-group-1:message:41", ingress_context.origin_payload["reply_to_external_message_key"]
    assert_equal "telegram:chat:telegram-group-1:message:41", ingress_context.origin_payload["quoted_external_message_key"]
    assert_equal "Earlier targeted message", ingress_context.origin_payload["quoted_text"]
    assert_equal "Bob", ingress_context.origin_payload["quoted_sender_label"]
    assert_equal [{"modality" => "image", "file_id" => "photo-1"}], ingress_context.origin_payload["quoted_attachment_refs"]
  end

  private

  def dispatch_context
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
      config_payload: {},
      runtime_state_payload: {}
    )
    channel_session = ChannelSession.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      conversation: conversation,
      platform: "telegram",
      peer_kind: "group",
      peer_id: "telegram-group-1",
      thread_key: "topic-1",
      session_metadata: {}
    )

    context.merge(
      conversation: conversation,
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session
    )
  end

  def build_ingress_context(context, sender_id:, text:, active_turn: nil, reply_to_external_message_key: nil, quoted_external_message_key: nil, quoted_text: nil, quoted_sender_label: nil, quoted_attachment_refs: [])
    IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      active_turn: active_turn,
      coalesced_message_ids: ["channel-inbound-1"],
      envelope: IngressAPI::Envelope.new(
        platform: "telegram",
        driver: "telegram_bot_api",
        ingress_binding_public_id: context[:ingress_binding].public_id,
        channel_connector_public_id: context[:channel_connector].public_id,
        external_event_key: "telegram:update:#{next_test_sequence}",
        external_message_key: "telegram:chat:telegram-group-1:message:#{next_test_sequence}",
        peer_kind: "group",
        peer_id: "telegram-group-1",
        thread_key: "topic-1",
        external_sender_id: sender_id,
        sender_snapshot: { "label" => sender_id },
        text: text,
        attachments: [],
        reply_to_external_message_key: reply_to_external_message_key,
        quoted_external_message_key: quoted_external_message_key,
        quoted_text: quoted_text,
        quoted_sender_label: quoted_sender_label,
        quoted_attachment_refs: quoted_attachment_refs,
        occurred_at: Time.current,
        transport_metadata: {},
        raw_payload: { "text" => text }
      ),
      pipeline_trace: []
    )
  end

  def create_channel_turn!(context, sender_id:, content:)
    turn = Turn.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      user: context[:conversation].user,
      workspace: context[:conversation].workspace,
      agent: context[:conversation].agent,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      execution_runtime_version: context[:execution_runtime].current_execution_runtime_version,
      execution_epoch: initialize_current_execution_epoch!(context[:conversation], execution_runtime: context[:execution_runtime]),
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "channel_ingress",
      origin_payload: {
        "external_sender_id" => sender_id,
      },
      source_ref_type: "ChannelInboundMessage",
      source_ref_id: "channel-inbound-1",
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: 1,
      agent_config_content_fingerprint: context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    input = UserMessage.create!(
      installation: context[:conversation].installation,
      conversation: context[:conversation],
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: content
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: input)
    turn
  end
end
