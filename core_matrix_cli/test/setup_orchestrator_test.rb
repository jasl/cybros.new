require "test_helper"

class CoreMatrixCLISetupOrchestratorTest < CoreMatrixCLITestCase
  def test_prime_workspace_context_prefers_active_workspace_agent_over_revoked_first_entry
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.workspaces_response = {
      "workspaces" => [
        {
          "workspace_id" => "ws_123",
          "name" => "Primary Workspace",
          "is_default" => true,
          "workspace_agents" => [
            {
              "workspace_agent_id" => "wa_revoked",
              "lifecycle_state" => "revoked",
            },
            {
              "workspace_agent_id" => "wa_active",
              "lifecycle_state" => "active",
            },
          ],
        },
      ],
    }

    payload = CoreMatrixCLI::SetupOrchestrator.new(runtime: runtime).prime_workspace_context!

    assert_equal "wa_active", payload.dig("workspace_agent", "workspace_agent_id")
    assert_equal "wa_active", runtime.config_store.read.fetch("workspace_agent_id")
  end
end
