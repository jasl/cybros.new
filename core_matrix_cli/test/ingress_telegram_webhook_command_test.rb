require "test_helper"

class CoreMatrixCLITelegramWebhookCommandTest < CoreMatrixCLITestCase
  def test_telegram_webhook_setup_creates_binding_when_missing_and_prints_webhook_material
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.persist_workspace_context(workspace_agent_id: "wa_123")
    runtime.create_ingress_binding_responses["telegram_webhook"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tgwh_123",
        "setup" => {
          "webhook_path" => "/ingress_api/telegram/bindings/pub_tgwh_123/updates",
        },
      },
    }
    runtime.update_ingress_binding_responses["ib_tgwh_123"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tgwh_123",
        "setup" => {
          "webhook_path" => "/ingress_api/telegram/bindings/pub_tgwh_123/updates",
          "webhook_secret_token" => "secret_tgwh_123",
        },
      },
    }

    output = run_cli(
      "ingress", "telegram-webhook", "setup",
      input: "456:def\nhttps://bot.example.com\n",
      runtime: runtime
    )

    assert_includes output, "https://bot.example.com/ingress_api/telegram/bindings/pub_tgwh_123/updates"
    assert_includes output, "X-Telegram-Bot-Api-Secret-Token"
    assert_equal "ib_tgwh_123", runtime.config_store.read.fetch("telegram_webhook_ingress_binding_id")
  end

  def test_telegram_webhook_help_explains_operator_preparation
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("ingress", "telegram-webhook", "help", "setup", runtime: runtime)

    assert_includes output, "cmctl ingress telegram-webhook setup"
    assert_includes output, "public HTTPS base URL"
    assert_includes output, "secret token"
    assert_includes output, "different Telegram bot tokens"
  end
end
