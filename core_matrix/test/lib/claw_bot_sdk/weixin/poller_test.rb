require "test_helper"

class ClawBotSDK::Weixin::PollerTest < ActiveSupport::TestCase
  test "polls using the connector cursor and persists the returned cursor" do
    connector = create_weixin_connector!
    connector.update!(
      runtime_state_payload: {
        "base_url" => "https://weixin.example",
        "bot_token" => "bot-token",
        "get_updates_buf" => "cursor-1"
      }
    )
    fake_client = Struct.new(:calls) do
      def get_updates(get_updates_buf:)
        calls << get_updates_buf
        {
          "ret" => 0,
          "msgs" => [{ "message_id" => "wx-msg-1" }],
          "get_updates_buf" => "cursor-2"
        }
      end
    end.new([])

    messages = ClawBotSDK::Weixin::Poller.call(
      channel_connector: connector,
      client: fake_client
    )

    assert_equal ["cursor-1"], fake_client.calls
    assert_equal ["wx-msg-1"], messages.map { |message| message.fetch("message_id") }
    assert_equal "cursor-2", connector.reload.runtime_state_payload["get_updates_buf"]
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
      runtime_state_payload: {}
    )
  end
end
