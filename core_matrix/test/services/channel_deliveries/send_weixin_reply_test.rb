require "test_helper"

class ChannelDeliveries::SendWeixinReplyTest < ActiveSupport::TestCase
  test "sends typing status_progress using the stored context token and typing ticket" do
    context = weixin_delivery_context
    calls = []
    fake_client = Struct.new(:calls) do
      def send_typing(ilink_user_id:, typing_ticket:)
        calls << [ilink_user_id, typing_ticket]
      end
    end.new(calls)
    delivery = create_channel_delivery!(
      context,
      payload: {
        "delivery_mode" => "status_progress",
        "chat_action" => "typing",
      }
    )

    ChannelDeliveries::SendWeixinReply.call(channel_delivery: delivery, client: fake_client)

    assert_equal [["wx-user-1", "typing-ticket-1"]], calls
    assert_equal "delivered", delivery.reload.delivery_state
  end

  test "sends final text replies through the weixin client with the stored context token" do
    context = weixin_delivery_context
    calls = []
    fake_client = Struct.new(:calls) do
      def send_text(to_user_id:, text:, context_token:)
        calls << [to_user_id, text, context_token]
        { "message_id" => "wx-outbound-1" }
      end
    end.new(calls)
    delivery = create_channel_delivery!(
      context,
      payload: {
        "text" => "final weixin reply",
      }
    )

    ChannelDeliveries::SendWeixinReply.call(channel_delivery: delivery, client: fake_client)

    assert_equal [["wx-user-1", "final weixin reply", "ctx-1"]], calls
    assert_equal "delivered", delivery.reload.delivery_state
    assert_equal "weixin:peer:wx-user-1:message:wx-outbound-1", delivery.external_message_key
  end

  test "sends small transcript attachments through the media client" do
    context = weixin_delivery_context
    output_message = attach_selected_output!(create_turn_with_input!(context[:conversation]), content: "artifact delivery")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "small body"
    )
    calls = []
    fake_media_client = Struct.new(:calls) do
      def send_attachment(attachment:, to_user_id:, context_token:, text:)
        calls << [attachment.fetch("attachment_id"), to_user_id, context_token, text]
        { "message_id" => "wx-native-1" }
      end
    end.new(calls)
    delivery = create_channel_delivery!(
      context,
      message: output_message,
      payload: {
        "text" => "artifact delivery",
        "attachments" => [
          {
            "attachment_id" => attachment.public_id,
            "filename" => "artifact.txt",
            "modality" => "file",
          },
        ],
      }
    )

    ChannelDeliveries::SendWeixinReply.call(
      channel_delivery: delivery,
      client: Object.new,
      media_client: fake_media_client
    )

    assert_equal [[attachment.public_id, "wx-user-1", "ctx-1", "artifact delivery"]], calls
    assert_equal "weixin:peer:wx-user-1:message:wx-native-1", delivery.reload.external_message_key
  end

  test "falls back to a signed download link for non-image transcript attachments at or above one megabyte" do
    context = weixin_delivery_context
    output_message = attach_selected_output!(create_turn_with_input!(context[:conversation]), content: "artifact delivery")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "artifact.txt",
      content_type: "text/plain",
      body: "a" * (1.megabyte + 1)
    )
    calls = []
    fake_client = Struct.new(:calls) do
      def send_text(to_user_id:, text:, context_token:)
        calls << [to_user_id, text, context_token]
        { "message_id" => "wx-outbound-1" }
      end
    end.new(calls)
    delivery = create_channel_delivery!(
      context,
      message: output_message,
      payload: {
        "text" => "artifact delivery",
        "attachments" => [
          {
            "attachment_id" => attachment.public_id,
            "filename" => "artifact.txt",
            "modality" => "file",
          },
        ],
      }
    )

    ChannelDeliveries::SendWeixinReply.call(channel_delivery: delivery, client: fake_client)

    assert_equal "wx-user-1", calls.first.first
    assert_equal "ctx-1", calls.first.third
    assert_includes calls.first.second, "artifact.txt"
    assert_match %r{https?://example.com/rails/active_storage/blobs/redirect/}, calls.first.second
    assert_equal "weixin:peer:wx-user-1:message:wx-outbound-1", delivery.reload.external_message_key
  end

  private

  def weixin_delivery_context
    context = create_workspace_context!
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )
    channel_connector = ChannelConnector.create!(
      installation: context[:installation],
      ingress_binding: ingress_binding,
      platform: "weixin",
      driver: "claw_bot_sdk_weixin",
      transport_kind: "poller",
      label: "Weixin Bot",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {
        "base_url" => "https://weixin.example",
        "bot_token" => "bot-token",
        "typing_ticket" => "typing-ticket-1",
      }
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
      platform: "weixin",
      peer_kind: "dm",
      peer_id: "wx-user-1",
      thread_key: nil,
      binding_state: "active",
      session_metadata: {
        "context_token" => "ctx-1",
      }
    )

    context.merge(
      ingress_binding: ingress_binding,
      channel_connector: channel_connector,
      channel_session: channel_session,
      conversation: conversation
    )
  end

  def create_channel_delivery!(context, **attrs)
    ChannelDelivery.create!({
      installation: context[:installation],
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector],
      channel_session: context[:channel_session],
      conversation: context[:conversation],
      external_message_key: "pending:#{SecureRandom.uuid}",
      payload: {},
      failure_payload: {},
    }.merge(attrs))
  end

  def create_turn_with_input!(conversation)
    Turns::StartUserTurn.call(
      conversation: conversation,
      content: "input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
  end
end
