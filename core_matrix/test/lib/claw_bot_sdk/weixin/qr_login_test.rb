require "test_helper"

class ClawBotSDK::Weixin::QrLoginTest < ActiveSupport::TestCase
  test "start marks the connector pending and surfaces qr_text when present" do
    connector = create_weixin_connector!(
      "qr_text" => "weixin://qr-login-token"
    )

    payload = ClawBotSDK::Weixin::QrLogin.start(channel_connector: connector)

    assert_equal "pending", payload.fetch("login_state")
    assert_equal "weixin://qr-login-token", payload.fetch("qr_text")
    assert connector.reload.runtime_state_payload.fetch("login_started_at").present?
  end

  test "status exposes qr fields alongside runtime state" do
    connector = create_weixin_connector!(
      "login_state" => "connected",
      "account_id" => "wx-account-1",
      "base_url" => "https://weixin.example",
      "qr_code_url" => "https://weixin.example/qr.png"
    )

    payload = ClawBotSDK::Weixin::QrLogin.status(channel_connector: connector)

    assert_equal "connected", payload.fetch("login_state")
    assert_equal "wx-account-1", payload.fetch("account_id")
    assert_equal "https://weixin.example", payload.fetch("base_url")
    assert_equal "https://weixin.example/qr.png", payload.fetch("qr_code_url")
  end

  private

  def create_weixin_connector!(runtime_state_payload = {})
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
      runtime_state_payload: runtime_state_payload
    )
  end
end
