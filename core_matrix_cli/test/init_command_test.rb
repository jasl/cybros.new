require "test_helper"

class CoreMatrixCLIInitCommandTest < CoreMatrixCLITestCase
  def test_init_bootstraps_and_persists_session_and_workspace_context
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.bootstrap_status_payload = { "bootstrap_state" => "unbootstrapped" }
    runtime.bootstrap_response = {
      "session_token" => "sess_123",
      "installation" => { "name" => "Primary Installation" },
      "user" => { "email" => "admin@example.com" },
      "workspace" => { "workspace_id" => "ws_123", "name" => "Primary Workspace" },
      "workspace_agent" => { "workspace_agent_id" => "wa_123" },
    }
    runtime.readiness_payload = {
      "authenticated" => true,
      "bootstrap_state" => "bootstrapped",
      "codex_subscription" => "missing",
    }

    output = run_cli(
      "init",
      input: "https://core.example.com\nPrimary Installation\nadmin@example.com\nPassword123!\nPassword123!\nPrimary Admin\n",
      runtime: runtime
    )

    assert_equal "sess_123", runtime.credential_store.read.fetch("session_token")
    assert_equal "ws_123", runtime.config_store.read.fetch("workspace_id")
    assert_equal "wa_123", runtime.config_store.read.fetch("workspace_agent_id")
    assert_includes output, "Primary Installation"
  end
end
