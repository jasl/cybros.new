require "test_helper"

class ChannelIngressFollowUpFlowTest < ActionDispatch::IntegrationTest
  InboundMessage = Struct.new(:public_id)

  test "channel ingress input steers before the side-effect boundary and queues after it" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])

    active_turn = Turns::StartChannelIngressTurn.call(
      conversation: conversation,
      channel_inbound_message: InboundMessage.new("channel_inbound_message_1"),
      content: "First inbound input",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_1",
        "external_sender_id" => "telegram:user:42",
      },
      selector_source: "conversation",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    steered = Turns::SteerCurrentInput.call(
      turn: active_turn,
      content: "Revised inbound input"
    )

    assert_equal active_turn.id, steered.id
    assert_equal "Revised inbound input", steered.selected_input_message.content

    attach_selected_output!(active_turn, content: "Streaming output")

    queued_turn = Turns::SteerCurrentInput.call(
      turn: active_turn.reload,
      content: "Queued inbound follow up",
      policy_mode: "queue",
      source_ref_type: "ChannelInboundMessage",
      source_ref_id: "channel_inbound_message_2",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_2",
        "external_sender_id" => "telegram:user:42",
      }
    )

    assert queued_turn.queued?
    assert_equal "channel_ingress", queued_turn.origin_kind
    assert_equal "ChannelInboundMessage", queued_turn.source_ref_type
    assert_equal "channel_inbound_message_2", queued_turn.source_ref_id
  end
end
