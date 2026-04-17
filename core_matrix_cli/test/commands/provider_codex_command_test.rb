require "test_helper"

class ProviderCodexCommandTest < CoreMatrixCLITestCase
  def test_codex_help_uses_full_nested_command_path
    output = run_cli("providers", "codex", "help", "login")

    assert_includes output, "cmctl providers codex login"
  end

  def test_codex_login_opens_verification_url_prints_user_code_and_polls_until_authorized
    api = FakeCoreMatrixAPI.new
    api.start_codex_authorization_response = {
      "authorization" => {
        "verification_uri" => "https://auth.example.test/device",
        "user_code" => "ABCD-EFGH",
        "poll_interval_seconds" => 0,
        "expires_at" => (Time.now + 60).utc.iso8601,
        "status" => "pending",
      },
    }
    api.poll_codex_authorization_sequence = [
      { "authorization" => { "status" => "pending" } },
      { "authorization" => { "status" => "authorized" } },
    ]
    browser_launcher = FakeBrowserLauncher.new
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli(
      "providers", "codex", "login",
      api: api,
      browser_launcher: browser_launcher,
      config_repository: config_repository
    )

    assert_equal ["https://auth.example.test/device"], browser_launcher.opened_urls
    assert_includes output, "Verification URL:"
    assert_includes output, "User code: ABCD-EFGH"
    assert_includes output, "authorized"
  end

  def test_codex_status_prints_current_authorization_state
    api = FakeCoreMatrixAPI.new
    api.codex_authorization_status_sequence = [
      { "authorization" => { "status" => "authorized" } },
    ]
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli("providers", "codex", "status", api: api, config_repository: config_repository)

    assert_includes output, "codex subscription: authorized"
  end

  def test_codex_logout_revokes_authorization_and_prints_missing
    api = FakeCoreMatrixAPI.new
    api.revoke_codex_authorization_response = {
      "authorization" => {
        "status" => "missing",
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    config_repository.merge("base_url" => "https://core.example.com")

    output = run_cli("providers", "codex", "logout", api: api, config_repository: config_repository)

    assert_includes output, "missing"
    assert_includes api.calls, [:revoke_codex_authorization]
  end
end
