require "test_helper"

class Turns::QueueChannelFollowUpTest < ActiveSupport::TestCase
  test "creates a queued follow up turn that preserves channel provenance" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "First input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    queued = Turns::QueueChannelFollowUp.call(
      conversation: conversation,
      content: "Inbound follow up",
      origin_payload: {
        "ingress_binding_id" => "ingress_binding_1",
        "channel_session_id" => "channel_session_1",
        "channel_inbound_message_id" => "channel_inbound_message_2",
        "external_sender_id" => "telegram:user:42",
      },
      source_ref_id: "channel_inbound_message_2",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    assert queued.queued?
    assert_equal "channel_ingress", queued.origin_kind
    assert_equal "ChannelInboundMessage", queued.source_ref_type
    assert_equal "channel_inbound_message_2", queued.source_ref_id
    assert_equal "channel_inbound_message_2", queued.origin_payload["channel_inbound_message_id"]
    assert_equal "telegram:user:42", queued.origin_payload["external_sender_id"]
  end
end
