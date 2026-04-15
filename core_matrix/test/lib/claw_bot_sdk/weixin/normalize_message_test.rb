require "test_helper"

class ClawBotSDK::Weixin::NormalizeMessageTest < ActiveSupport::TestCase
  test "normalizes a text direct message into a weixin ingress envelope" do
    context = create_weixin_ingress_context
    envelope = ClawBotSDK::Weixin::NormalizeMessage.call(
      message: {
        "message_id" => "wx-msg-1",
        "from_user_id" => "wx-user-1",
        "create_time_ms" => 1_713_600_000_000,
        "context_token" => "ctx-1",
        "item_list" => [
          {
            "type" => 1,
            "text_item" => { "text" => "hello from weixin" }
          }
        ]
      },
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector]
    )

    assert_equal "weixin", envelope.platform
    assert_equal "claw_bot_sdk_weixin", envelope.driver
    assert_equal "dm", envelope.peer_kind
    assert_equal "wx-user-1", envelope.peer_id
    assert_equal "wx-user-1", envelope.external_sender_id
    assert_equal "hello from weixin", envelope.text
    assert_equal "ctx-1", envelope.transport_metadata["context_token"]
  end

  test "synthesizes transcript text for media only messages and emits attachment descriptors" do
    context = create_weixin_ingress_context
    envelope = ClawBotSDK::Weixin::NormalizeMessage.call(
      message: {
        "message_id" => "wx-msg-2",
        "from_user_id" => "wx-user-1",
        "create_time_ms" => 1_713_600_000_000,
        "context_token" => "ctx-2",
        "item_list" => [
          {
            "type" => 2,
            "msg_id" => "item-image-1",
            "image_item" => {
              "url" => "https://weixin.example/image/1"
            }
          }
        ]
      },
      ingress_binding: context[:ingress_binding],
      channel_connector: context[:channel_connector]
    )

    assert_equal "User sent 1 attachment.", envelope.text
    assert_equal 1, envelope.attachments.length
    assert_equal "image", envelope.attachments.first["modality"]
    assert_equal "item-image-1", envelope.attachments.first["message_item_id"]
  end

  private

  def create_weixin_ingress_context
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
      runtime_state_payload: {}
    )

    context.merge(ingress_binding: ingress_binding, channel_connector: channel_connector)
  end
end
