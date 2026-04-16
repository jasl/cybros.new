require "test_helper"

class ChannelConnectors::DispatchActivePollersJobTest < ActiveJob::TestCase
  test "enqueues active configured poller connectors by platform" do
    telegram_connector = create_connector!(
      platform: "telegram",
      transport_kind: "poller",
      credential_ref_payload: { "bot_token" => "123:abc" }
    )
    weixin_connector = create_connector!(
      platform: "weixin",
      transport_kind: "poller",
      runtime_state_payload: {
        "base_url" => "https://weixin.example",
        "bot_token" => "weixin-token",
      }
    )
    create_connector!(
      platform: "telegram",
      transport_kind: "poller",
      lifecycle_state: "disabled",
      credential_ref_payload: { "bot_token" => "disabled-token" }
    )
    create_connector!(
      platform: "telegram_webhook",
      transport_kind: "webhook",
      credential_ref_payload: { "bot_token" => "webhook-token" },
      config_payload: { "webhook_base_url" => "https://bot.example.com" }
    )

    assert_enqueued_jobs 2 do
      ChannelConnectors::DispatchActivePollersJob.perform_now
    end

    assert_enqueued_with(job: ChannelConnectors::TelegramPollUpdatesJob, args: [telegram_connector.public_id])
    assert_enqueued_with(job: ChannelConnectors::WeixinPollAccountJob, args: [weixin_connector.public_id])
  end

  private

  def create_connector!(platform:, transport_kind:, lifecycle_state: "active", credential_ref_payload: {}, config_payload: {}, runtime_state_payload: {})
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
      platform: platform,
      driver: driver_for(platform),
      transport_kind: transport_kind,
      label: "#{platform.titleize} Connector",
      lifecycle_state: lifecycle_state,
      credential_ref_payload: credential_ref_payload,
      config_payload: config_payload,
      runtime_state_payload: runtime_state_payload
    )
  end

  def driver_for(platform)
    case platform
    when "weixin"
      "claw_bot_sdk_weixin"
    else
      "telegram_bot_api"
    end
  end
end
