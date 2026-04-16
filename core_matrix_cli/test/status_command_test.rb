require "test_helper"

class CoreMatrixCLIStatusCommandTest < CoreMatrixCLITestCase
  def test_status_reads_live_snapshot_and_prints_codex_state
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.readiness_payload = {
      "authenticated" => true,
      "bootstrap_state" => "bootstrapped",
      "default_workspace" => "present",
      "workspace_agent" => "present",
      "codex_subscription" => "authorized",
    }

    output = run_cli("status", runtime: runtime)

    assert_includes output, "codex subscription: authorized"
    assert_includes runtime.calls, [:readiness_snapshot]
  end
end
