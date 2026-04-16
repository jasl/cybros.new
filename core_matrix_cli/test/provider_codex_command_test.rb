require "test_helper"

class CoreMatrixCLICodexCommandTest < CoreMatrixCLITestCase
  def test_codex_help_uses_full_nested_command_path
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("providers", "codex", "help", "login", runtime: runtime)

    assert_includes output, "cmctl providers codex login"
  end

  def test_codex_login_opens_authorization_url_and_polls_until_authorized
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.start_codex_authorization_response = {
      "authorization" => {
        "authorization_url" => "https://auth.example.test/device",
        "status" => "pending",
      },
    }
    runtime.codex_authorization_status_sequence = [
      { "authorization" => { "status" => "pending" } },
      { "authorization" => { "status" => "authorized" } },
    ]
    browser_launcher = FakeBrowserLauncher.new

    output = run_cli(
      "providers", "codex", "login",
      runtime: runtime,
      browser_launcher: browser_launcher
    )

    assert_equal ["https://auth.example.test/device"], browser_launcher.opened_urls
    assert_includes output, "Open this URL if the browser does not launch:"
    assert_includes output, "authorized"
  end

  def test_codex_logout_revokes_authorization_and_prints_missing
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.revoke_codex_authorization_response = {
      "authorization" => {
        "status" => "missing",
      },
    }

    output = run_cli("providers", "codex", "logout", runtime: runtime)

    assert_includes output, "missing"
    assert_includes runtime.calls, [:revoke_codex_authorization]
  end
end
