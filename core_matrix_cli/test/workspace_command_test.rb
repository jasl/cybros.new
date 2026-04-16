require "test_helper"

class CoreMatrixCLIWorkspaceCommandTest < CoreMatrixCLITestCase
  def test_workspace_create_persists_selected_workspace
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.create_workspace_response = {
      "workspace" => {
        "workspace_id" => "ws_123",
        "name" => "Integration Lab",
      },
    }

    output = run_cli(
      "workspace", "create", "--name", "Integration Lab",
      runtime: runtime
    )

    assert_equal "ws_123", runtime.config_store.read.fetch("workspace_id")
    assert_includes output, "Integration Lab"
  end

  def test_workspace_use_updates_selected_workspace
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    run_cli("workspace", "use", "ws_456", runtime: runtime)

    assert_equal "ws_456", runtime.config_store.read.fetch("workspace_id")
  end

  def test_workspace_use_clears_stale_workspace_agent_and_binding_selection
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.config_store.write(
      "workspace_id" => "ws_old",
      "workspace_agent_id" => "wa_old",
      "telegram_ingress_binding_id" => "ib_tg_old",
      "weixin_ingress_binding_id" => "ib_wx_old"
    )

    run_cli("workspace", "use", "ws_456", runtime: runtime)

    assert_equal({ "workspace_id" => "ws_456" }, runtime.config_store.read)
  end
end
