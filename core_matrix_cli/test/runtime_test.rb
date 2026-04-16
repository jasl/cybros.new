require "test_helper"

class CoreMatrixCLIRuntimeTest < CoreMatrixCLITestCase
  def test_persist_workspace_context_clears_workspace_agent_and_binding_state_when_workspace_changes
    runtime = CoreMatrixCLI::Runtime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    runtime.config_store.write(
      "workspace_id" => "ws_old",
      "workspace_agent_id" => "wa_old",
      "telegram_ingress_binding_id" => "ib_tg_old",
      "weixin_ingress_binding_id" => "ib_wx_old"
    )

    runtime.persist_workspace_context(workspace_id: "ws_new")

    assert_equal(
      {
        "workspace_id" => "ws_new",
      },
      runtime.config_store.read
    )
  end

  def test_persist_workspace_context_clears_binding_state_when_workspace_agent_changes
    runtime = CoreMatrixCLI::Runtime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    runtime.config_store.write(
      "workspace_id" => "ws_123",
      "workspace_agent_id" => "wa_old",
      "telegram_ingress_binding_id" => "ib_tg_old",
      "weixin_ingress_binding_id" => "ib_wx_old"
    )

    runtime.persist_workspace_context(workspace_id: "ws_123", workspace_agent_id: "wa_new")

    assert_equal(
      {
        "workspace_id" => "ws_123",
        "workspace_agent_id" => "wa_new",
      },
      runtime.config_store.read
    )
  end
end
