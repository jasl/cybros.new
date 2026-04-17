require "test_helper"

class IngressTelegramCommandTest < CoreMatrixCLITestCase
  def test_telegram_setup_creates_polling_binding_when_missing_and_prints_poller_material
    api = FakeCoreMatrixAPI.new
    api.create_ingress_binding_responses["telegram"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tg_123",
        "setup" => {
          "poller_binding_id" => "pub_tg_123",
        },
      },
    }
    api.update_ingress_binding_responses["ib_tg_123"] = {
      "ingress_binding" => {
        "ingress_binding_id" => "ib_tg_123",
        "setup" => {
          "poller_binding_id" => "pub_tg_123",
        },
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.write(
      "base_url" => "https://core.example.com",
      "workspace_agent_id" => "wa_123"
    )

    output = run_cli(
      "ingress", "telegram", "setup",
      input: "123:abc\n",
      api: api,
      config_repository: config_repository
    )

    assert_includes output, "Polling Binding ID: pub_tg_123"
    refute_includes output, "Webhook URL:"
    assert_equal "ib_tg_123", config_repository.read.fetch("telegram_ingress_binding_id")
  end

  def test_telegram_help_explains_polling_operator_preparation
    output = run_cli("ingress", "telegram", "help", "setup")

    assert_includes output, "cmctl ingress telegram setup"
    assert_includes output, "BotFather"
    assert_includes output, "queue worker"
    assert_includes output, "different Telegram bot tokens"
  end

  def test_telegram_setup_explains_how_to_select_a_workspace_agent_when_missing
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli("ingress", "telegram", "setup", config_repository: config_repository)

    assert_includes output, "No workspace agent is selected."
    assert_includes output, "cmctl agent attach"
  end
end
