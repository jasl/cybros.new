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
      "installation_name" => "Primary Installation",
      "default_workspace" => "present",
      "workspace_agent" => "present",
      "codex_subscription" => "authorized",
    }

    output = run_cli("status", runtime: runtime)

    assert_includes output, "Base URL: https://core.example.com"
    assert_includes output, "Installation: Primary Installation"
    assert_includes output, "codex subscription: authorized"
    assert_includes runtime.calls, [:readiness_snapshot]
  end

  def test_status_explains_how_to_configure_base_url_when_missing
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("status", runtime: runtime)

    assert_includes output, "No CoreMatrix base URL is configured."
    assert_includes output, "cmctl init"
  end
end
