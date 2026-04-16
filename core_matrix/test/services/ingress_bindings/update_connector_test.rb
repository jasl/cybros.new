require "test_helper"

class IngressBindings::UpdateConnectorTest < ActiveSupport::TestCase
  test "updates telegram connector credentials and config" do
    connector = create_telegram_connector!

    IngressBindings::UpdateConnector.call(
      channel_connector: connector,
      attributes: {
        "credential_ref_payload" => { "bot_token" => "123:abc" },
        "config_payload" => { "webhook_base_url" => "https://bot.example.com" },
      }
    )

    connector.reload
    assert_equal "123:abc", connector.credential_ref_payload.fetch("bot_token")
    assert_equal "https://bot.example.com", connector.config_payload.fetch("webhook_base_url")
  end

  test "rejects blank telegram bot token" do
    connector = create_telegram_connector!

    assert_raises(ActiveRecord::RecordInvalid) do
      IngressBindings::UpdateConnector.call(
        channel_connector: connector,
        attributes: {
          "credential_ref_payload" => { "bot_token" => " " },
        }
      )
    end
  end

  test "rejects invalid webhook base url" do
    connector = create_telegram_connector!

    assert_raises(ActiveRecord::RecordInvalid) do
      IngressBindings::UpdateConnector.call(
        channel_connector: connector,
        attributes: {
          "config_payload" => { "webhook_base_url" => "ftp://bot.example.com" },
        }
      )
    end
  end

  test "allows label only updates" do
    connector = create_telegram_connector!

    IngressBindings::UpdateConnector.call(
      channel_connector: connector,
      attributes: {
        "label" => "Ops Telegram",
      }
    )

    assert_equal "Ops Telegram", connector.reload.label
  end

  private

  def create_telegram_connector!
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
      platform: "telegram",
      driver: "telegram_bot_api",
      transport_kind: "webhook",
      label: "Telegram Bot",
      lifecycle_state: "active",
      credential_ref_payload: {},
      config_payload: {},
      runtime_state_payload: {}
    )
  end
end
