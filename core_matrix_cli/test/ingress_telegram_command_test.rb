require "test_helper"

class CoreMatrixCLITelegramCommandTest < CoreMatrixCLITestCase
  def test_telegram_setup_creates_binding_when_missing_and_prints_webhook_material
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.persist_workspace_context(workspace_agent_id: "wa_123")
    runtime.create_ingress_binding_responses["telegram"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tg_123",
        "setup" => {
          "webhook_path" => "/ingress_api/telegram/bindings/pub_tg_123/updates",
        },
      },
    }
    runtime.update_ingress_binding_responses["ib_tg_123"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tg_123",
        "setup" => {
          "webhook_path" => "/ingress_api/telegram/bindings/pub_tg_123/updates",
          "webhook_secret_token" => "secret_tg_123",
        },
      },
    }

    output = run_cli(
      "ingress", "telegram", "setup",
      input: "123:abc\nhttps://bot.example.com\n",
      runtime: runtime
    )

    assert_includes output, "https://bot.example.com/ingress_api/telegram/bindings/pub_tg_123/updates"
    assert_includes output, "X-Telegram-Bot-Api-Secret-Token"
    assert_equal "ib_tg_123", runtime.config_store.read.fetch("telegram_ingress_binding_id")
  end

  def test_telegram_help_explains_operator_preparation
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("ingress", "telegram", "help", "setup", runtime: runtime)

    assert_includes output, "BotFather"
    assert_includes output, "secret token"
  end

  def test_telegram_setup_explains_how_to_select_a_workspace_agent_when_missing
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")

    output = run_cli("ingress", "telegram", "setup", runtime: runtime)

    assert_includes output, "No workspace agent is selected."
    assert_includes output, "cmctl agent attach"
  end
end
