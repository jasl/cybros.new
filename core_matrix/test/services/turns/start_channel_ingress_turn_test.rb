require "test_helper"

class Turns::StartChannelIngressTurnTest < ActiveSupport::TestCase
  InboundMessage = Struct.new(:public_id)

  test "creates an active channel ingress turn with bootstrap workflow state and provenance" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    inbound_message = InboundMessage.new("channel_inbound_message_1")
    origin_payload = {
      "ingress_binding_id" => "ingress_binding_1",
      "channel_session_id" => "channel_session_1",
      "channel_inbound_message_id" => inbound_message.public_id,
      "external_sender_id" => "telegram:user:42",
    }

    turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: inbound_message,
      content: "Inbound channel text",
      origin_payload: origin_payload,
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    assert turn.active?
    assert_equal "channel_ingress", turn.origin_kind
    assert_equal "ChannelInboundMessage", turn.source_ref_type
    assert_equal inbound_message.public_id, turn.source_ref_id
    assert_equal origin_payload, turn.origin_payload
    assert_equal "pending", turn.workflow_bootstrap_state
    assert_equal "conversation", turn.workflow_bootstrap_payload["selector_source"]
    assert_equal "candidate:codex_subscription/gpt-5.3-codex", turn.workflow_bootstrap_payload["selector"]
    assert_instance_of UserMessage, turn.selected_input_message
    assert_equal "Inbound channel text", turn.selected_input_message.content
  end

  test "rejects non-interactive conversations" do
    context = create_workspace_context!
    conversation = Conversations::CreateAutomationRoot.call(workspace: context[:workspace])

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Turns::StartChannelIngressTurn.call(
        conversation: conversation,
        channel_inbound_message: InboundMessage.new("channel_inbound_message_2"),
        content: "Blocked inbound text",
        origin_payload: {
          "ingress_binding_id" => "ingress_binding_1",
          "channel_session_id" => "channel_session_1",
          "channel_inbound_message_id" => "channel_inbound_message_2",
        },
        selector_source: "conversation",
        selector: "candidate:codex_subscription/gpt-5.3-codex"
      )
    end

    assert_includes error.record.errors[:purpose], "must be interactive for channel ingress turn entry"
  end

  test "requires external sender provenance in the origin payload" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    error = assert_raises(ArgumentError) do
      Turns::StartChannelIngressTurn.call(
        conversation: conversation,
        channel_inbound_message: InboundMessage.new("channel_inbound_message_3"),
        content: "Inbound channel text",
        origin_payload: {
          "ingress_binding_id" => "ingress_binding_1",
          "channel_session_id" => "channel_session_1",
          "channel_inbound_message_id" => "channel_inbound_message_3",
        },
        selector_source: "conversation",
        selector: "candidate:codex_subscription/gpt-5.3-codex"
      )
    end

    assert_equal "origin_payload must include external_sender_id", error.message
  end

  test "allows channel ingress for managed channel conversations even when main transcript entry is disabled" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      workspace_agent: context[:workspace_agent],
      agent: context[:agent],
      execution_runtime: context[:execution_runtime],
      entry_policy_payload: Conversation.channel_managed_entry_policy_payload(
        base_policy_payload: context[:workspace_agent].entry_policy_payload,
        purpose: "interactive"
      )
    )

    turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: InboundMessage.new("channel_inbound_message_4"),
      content: "Inbound channel text",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_4",
        "external_sender_id" => "telegram:user:42",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    assert turn.active?
    assert_equal "channel_ingress", turn.origin_kind
  end
end
