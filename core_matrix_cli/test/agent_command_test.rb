require "test_helper"

class CoreMatrixCLIAgentCommandTest < CoreMatrixCLITestCase
  def test_agent_attach_persists_workspace_agent_selection
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.attach_workspace_agent_response = {
      "workspace_agent" => {
        "workspace_agent_id" => "wa_123",
        "workspace_id" => "ws_123",
        "agent_id" => "agt_123",
      },
    }

    output = run_cli(
      "agent", "attach", "--workspace-id", "ws_123", "--agent-id", "agt_123",
      runtime: runtime
    )

    assert_equal "wa_123", runtime.config_store.read.fetch("workspace_agent_id")
    assert_includes output, "wa_123"
  end
end
