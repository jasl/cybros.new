require "test_helper"

class IngressAPI::Preprocessors::CoalesceBurstTest < ActiveSupport::TestCase
  test "merges same sender pre-side-effect follow up text into one dispatch input" do
    context = burst_context
    active_turn = create_channel_turn!(
      context,
      conversation: context[:conversation],
      sender_id: "telegram-user-1",
      content: "First part",
      merged_inbound_ids: ["channel-inbound-1"]
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      active_turn: active_turn,
      coalesced_message_ids: ["channel-inbound-2"],
      envelope: envelope_for(context, sender_id: "telegram-user-1", text: "Second part"),
      pipeline_trace: []
    )

    IngressAPI::Preprocessors::CoalesceBurst.call(context: ingress_context)

    assert_equal "First part\nSecond part", ingress_context.envelope.text
    assert_equal ["channel-inbound-1", "channel-inbound-2"], ingress_context.coalesced_message_ids
  end

  test "does not merge cross sender input in a shared conversation" do
    context = burst_context
    active_turn = create_channel_turn!(
      context,
      conversation: context[:conversation],
      sender_id: "telegram-user-1",
      content: "First part",
      merged_inbound_ids: ["channel-inbound-1"]
    )
    ingress_context = IngressAPI::Context.new(
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      active_turn: active_turn,
      coalesced_message_ids: ["channel-inbound-2"],
      envelope: envelope_for(context, sender_id: "telegram-user-2", text: "Other sender"),
      pipeline_trace: []
    )

    IngressAPI::Preprocessors::CoalesceBurst.call(context: ingress_context)

    assert_equal "Other sender", ingress_context.envelope.text
    assert_equal ["channel-inbound-2"], ingress_context.coalesced_message_ids
  end

  private

  def burst_context
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
        "bot_token" => "telegram-bot-token"
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

  def create_channel_turn!(context, conversation:, sender_id:, content:, merged_inbound_ids:)
    turn = Turn.create!(
      installation: conversation.installation,
      conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      agent_definition_version: context[:agent_definition_version],
      execution_runtime: context[:execution_runtime],
      execution_runtime_version: context[:execution_runtime].current_execution_runtime_version,
      execution_epoch: initialize_current_execution_epoch!(conversation, execution_runtime: context[:execution_runtime]),
      sequence: 1,
      lifecycle_state: "active",
      origin_kind: "channel_ingress",
      origin_payload: {
        "external_sender_id" => sender_id,
        "merged_inbound_message_ids" => merged_inbound_ids,
      },
      source_ref_type: "ChannelInboundMessage",
      source_ref_id: merged_inbound_ids.last,
      pinned_agent_definition_fingerprint: context[:agent_definition_version].definition_fingerprint,
      agent_config_version: 1,
      agent_config_content_fingerprint: context[:agent_definition_version].definition_fingerprint,
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    input = UserMessage.create!(
      installation: conversation.installation,
      conversation: conversation,
      turn: turn,
      role: "user",
      slot: "input",
      variant_index: 0,
      content: content
    )
    Turns::PersistSelectionState.call(turn: turn, selected_input_message: input)
    turn
  end

  def envelope_for(context, sender_id:, text:)
    IngressAPI::Envelope.new(
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
