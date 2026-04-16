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

  def test_agent_attach_explains_how_to_select_a_workspace_when_missing
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")

    output = run_cli(
      "agent", "attach", "--agent-id", "agt_123",
      runtime: runtime
    )

    assert_includes output, "No workspace is selected."
    assert_includes output, "cmctl workspace use"
  end
end
