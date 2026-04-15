require "test_helper"

class ChannelConnectors::WeixinPollAccountJobTest < ActiveJob::TestCase
  test "polls the connector and feeds each message into the ingress receive service" do
    connector = create_weixin_connector!
    poller_calls = []
    receiver_calls = []
    fake_poller = lambda do |channel_connector:|
      poller_calls << channel_connector.public_id
      [
        { "message_id" => "wx-msg-1" },
        { "message_id" => "wx-msg-2" }
      ]
    end
    fake_receiver = lambda do |channel_connector:, message:|
      receiver_calls << [channel_connector.public_id, message.fetch("message_id")]
    end

    ChannelConnectors::WeixinPollAccountJob.perform_now(
      connector.public_id,
      poller: fake_poller,
      receiver: fake_receiver
    )

    assert_equal [connector.public_id], poller_calls
    assert_equal [
      [connector.public_id, "wx-msg-1"],
      [connector.public_id, "wx-msg-2"]
    ], receiver_calls
  end

  private

  def create_weixin_connector!
    context = create_workspace_context!
    ingress_binding = IngressBinding.create!(
      installation: context[:installation],
      workspace_agent: context[:workspace_agent],
      default_execution_runtime: context[:execution_runtime],
      routing_policy_payload: {},
      manual_entry_policy: IngressBinding::DEFAULT_MANUAL_ENTRY_POLICY
    )
    ChannelConnector.create!(
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
        "bot_token" => "bot-token"
      }
    )
  end
end
