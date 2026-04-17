require "test_helper"

class AgentCommandTest < CoreMatrixCLITestCase
  def test_agent_attach_persists_workspace_agent_selection
    api = FakeCoreMatrixAPI.new
    api.attach_workspace_agent_response = {
      "workspace_agent" => {
        "workspace_agent_id" => "wa_123",
        "workspace_id" => "ws_123",
        "agent_id" => "agt_123",
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli(
      "agent", "attach", "--workspace-id", "ws_123", "--agent-id", "agt_123",
      api: api,
      config_repository: config_repository
    )

    assert_equal "ws_123", config_repository.read.fetch("workspace_id")
    assert_equal "wa_123", config_repository.read.fetch("workspace_agent_id")
    assert_includes output, "wa_123"
  end

  def test_agent_attach_clears_stale_binding_selection_when_workspace_mount_changes
    api = FakeCoreMatrixAPI.new
    api.attach_workspace_agent_response = {
      "workspace_agent" => {
        "workspace_agent_id" => "wa_123",
        "workspace_id" => "ws_123",
        "agent_id" => "agt_123",
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.write(
      "base_url" => "https://core.example.com",
      "workspace_id" => "ws_old",
      "workspace_agent_id" => "wa_old",
      "telegram_ingress_binding_id" => "ib_tg_old",
      "telegram_webhook_ingress_binding_id" => "ib_tgwh_old",
      "weixin_ingress_binding_id" => "ib_wx_old"
    )

    run_cli(
      "agent", "attach", "--workspace-id", "ws_123", "--agent-id", "agt_123",
      api: api,
      config_repository: config_repository
    )

    assert_equal(
      {
        "base_url" => "https://core.example.com",
        "workspace_id" => "ws_123",
        "workspace_agent_id" => "wa_123",
      },
      config_repository.read
    )
  end

  def test_agent_attach_explains_how_to_select_a_workspace_when_missing
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli(
      "agent", "attach", "--agent-id", "agt_123",
      config_repository: config_repository
    )

    assert_includes output, "No workspace is selected."
    assert_includes output, "cmctl workspace use"
  end
end
