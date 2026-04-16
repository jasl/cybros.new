require "test_helper"

class CoreMatrixCLIAuthCommandTest < CoreMatrixCLITestCase
  def test_auth_help_hides_internal_tree_command
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )

    output = run_cli("auth", "help", runtime: runtime)

    refute_includes output, "auth_c_l_i tree"
  end

  def test_login_persists_session_token_and_operator_email
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.login_response = {
      "session_token" => "sess_123",
      "user" => {
        "email" => "admin@example.com",
        "display_name" => "Primary Admin",
      },
    }

    output = run_cli(
      "auth", "login",
      input: "https://core.example.com\nadmin@example.com\nPassword123!\n",
      runtime: runtime
    )

    assert_equal "sess_123", runtime.credential_store.read.fetch("session_token")
    assert_equal "admin@example.com", runtime.config_store.read.fetch("operator_email")
    assert_includes output, "admin@example.com"
  end

  def test_login_accepts_password_prompt_input_from_non_tty_stdin
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.login_response = {
      "session_token" => "sess_123",
      "user" => {
        "email" => "admin@example.com",
        "display_name" => "Primary Admin",
      },
    }

    output = run_cli(
      "auth", "login",
      runtime: runtime,
      input_io: NonTtyInput.new("https://core.example.com\nadmin@example.com\nPassword123!\n")
    )

    assert_equal "sess_123", runtime.credential_store.read.fetch("session_token")
    assert_includes output, "admin@example.com"
  end

  def test_logout_revokes_server_session_and_clears_local_token
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.persist_session_token("sess_123")

    run_cli("auth", "logout", runtime: runtime)

    assert_equal({}, runtime.credential_store.read)
    assert_includes runtime.calls, [:logout]
  end

  def test_whoami_explains_when_session_is_expired
    runtime = FakeRuntime.new(
      config_store: CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json")),
      credential_store: CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    )
    runtime.persist_base_url("https://core.example.com")
    runtime.persist_session_token("sess_123")

    def runtime.current_session
      raise CoreMatrixCLI::HTTPClient::UnauthorizedError.new(
        "unauthorized",
        status: 401,
        payload: { "error" => "unauthorized" }
      )
    end

    output = run_cli("auth", "whoami", runtime: runtime)

    assert_equal({}, runtime.credential_store.read)
    assert_includes output, "Session expired or revoked."
    assert_includes output, "cmctl auth login"
  end
end
