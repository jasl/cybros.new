require "test_helper"

class IngressTelegramWebhookCommandTest < CoreMatrixCLITestCase
  def test_telegram_webhook_setup_creates_binding_when_missing_and_prints_webhook_material
    api = FakeCoreMatrixAPI.new
    api.create_ingress_binding_responses["telegram_webhook"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tgwh_123",
        "setup" => {
          "webhook_path" => "/ingress_api/telegram/bindings/pub_tgwh_123/updates",
        },
      },
    }
    api.update_ingress_binding_responses["ib_tgwh_123"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tgwh_123",
        "setup" => {
          "webhook_path" => "/ingress_api/telegram/bindings/pub_tgwh_123/updates",
          "webhook_secret_token" => "secret_tgwh_123",
        },
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.write(
      "base_url" => "https://core.example.com",
      "workspace_agent_id" => "wa_123"
    )

    output = run_cli(
      "ingress", "telegram-webhook", "setup",
      input: "456:def\nhttps://bot.example.com\n",
      api: api,
      config_repository: config_repository
    )

    assert_includes output, "https://bot.example.com/ingress_api/telegram/bindings/pub_tgwh_123/updates"
    assert_includes output, "X-Telegram-Bot-Api-Secret-Token"
    assert_equal "ib_tgwh_123", config_repository.read.fetch("telegram_webhook_ingress_binding_id")
  end

  def test_telegram_webhook_help_explains_operator_preparation
    output = run_cli("ingress", "telegram-webhook", "help", "setup")

    assert_includes output, "cmctl ingress telegram-webhook setup"
    assert_includes output, "public HTTPS base URL"
    assert_includes output, "secret token"
    assert_includes output, "different Telegram bot tokens"
  end
end
