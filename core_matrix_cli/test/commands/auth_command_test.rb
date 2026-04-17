require "test_helper"

class AuthCommandTest < CoreMatrixCLITestCase
  def test_auth_help_hides_internal_tree_command
    output = run_cli("auth", "help")

    refute_includes output, "auth tree"
  end

  def test_login_persists_session_token_and_operator_email
    api = FakeCoreMatrixAPI.new
    api.login_response = {
      "session_token" => "sess_123",
      "user" => {
        "email" => "admin@example.com",
        "display_name" => "Primary Admin",
      },
    }
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))

    output = run_cli(
      "auth", "login",
      input: "https://core.example.com\nadmin@example.com\nPassword123!\n",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    assert_equal "https://core.example.com", config_repository.read.fetch("base_url")
    assert_equal "admin@example.com", config_repository.read.fetch("operator_email")
    assert_equal "sess_123", credential_repository.read.fetch("session_token")
    assert_includes output, "admin@example.com"
  end

  def test_login_accepts_password_prompt_input_from_non_tty_stdin
    api = FakeCoreMatrixAPI.new
    api.login_response = {
      "session_token" => "sess_123",
      "user" => {
        "email" => "admin@example.com",
      },
    }
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))

    output = run_cli(
      "auth", "login",
      api: api,
      credential_repository: credential_repository,
      input_io: NonTtyInput.new("https://core.example.com\nadmin@example.com\nPassword123!\n")
    )

    assert_equal "sess_123", credential_repository.read.fetch("session_token")
    assert_includes output, "admin@example.com"
  end

  def test_logout_revokes_server_session_and_clears_local_token
    api = FakeCoreMatrixAPI.new
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    config_repository.merge("base_url" => "https://core.example.com")
    credential_repository.write("session_token" => "sess_123")

    run_cli(
      "auth", "logout",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    assert_equal({}, credential_repository.read)
    assert_includes api.calls, [:logout]
  end

  def test_whoami_explains_when_session_is_expired
    api = FakeCoreMatrixAPI.new
    def api.current_session
      raise CoreMatrixCLI::Errors::UnauthorizedError.new(
        "unauthorized",
        status: 401,
        payload: { "error" => "unauthorized" }
      )
    end
    config_repository = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    credential_repository = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    config_repository.merge("base_url" => "https://core.example.com")
    credential_repository.write("session_token" => "sess_123")

    output = run_cli(
      "auth", "whoami",
      api: api,
      config_repository: config_repository,
      credential_repository: credential_repository
    )

    assert_equal({}, credential_repository.read)
    assert_includes output, "Session expired or revoked."
    assert_includes output, "cmctl auth login"
  end
end
