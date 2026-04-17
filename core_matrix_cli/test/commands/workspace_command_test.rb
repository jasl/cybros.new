require "test_helper"

class WorkspaceCommandTest < CoreMatrixCLITestCase
  def test_workspace_list_prints_available_workspaces
    api = FakeCoreMatrixAPI.new
    api.workspaces_response = {
      "workspaces" => [
        { "workspace_id" => "ws_123", "name" => "CLI Smoke Workspace", "is_default" => true },
        { "workspace_id" => "ws_456", "name" => "Integration Lab", "is_default" => false },
      ],
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli("workspace", "list", api: api, config_repository: config_repository)

    assert_includes output, "* ws_123 CLI Smoke Workspace"
    assert_includes output, "- ws_456 Integration Lab"
  end

  def test_workspace_create_persists_selected_workspace
    api = FakeCoreMatrixAPI.new
    api.create_workspace_response = {
      "workspace" => {
        "workspace_id" => "ws_123",
        "name" => "Integration Lab",
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli(
      "workspace", "create", "--name", "Integration Lab",
      api: api,
      config_repository: config_repository
    )

    assert_equal "ws_123", config_repository.read.fetch("workspace_id")
    assert_includes output, "Integration Lab"
  end

  def test_workspace_use_updates_selected_workspace
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))

    run_cli("workspace", "use", "ws_456", config_repository: config_repository)

    assert_equal "ws_456", config_repository.read.fetch("workspace_id")
  end

  def test_workspace_use_clears_stale_workspace_agent_and_binding_selection
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.write(
      "workspace_id" => "ws_old",
      "workspace_agent_id" => "wa_old",
      "telegram_ingress_binding_id" => "ib_tg_old",
      "telegram_webhook_ingress_binding_id" => "ib_tgwh_old",
      "weixin_ingress_binding_id" => "ib_wx_old"
    )

    run_cli("workspace", "use", "ws_456", config_repository: config_repository)

    assert_equal({ "workspace_id" => "ws_456" }, config_repository.read)
  end
end
