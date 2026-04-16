require "test_helper"

class CoreMatrixCLICredentialStoreTest < CoreMatrixCLITestCase
  def test_file_store_writes_with_0600_permissions
    store = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))

    store.write("session_token" => "secret")

    assert_equal "600", format("%o", File.stat(tmp_path("credentials.json")).mode & 0o777)
    assert_equal({ "session_token" => "secret" }, store.read)
  end

  def test_file_store_clear_removes_credentials
    store = CoreMatrixCLI::CredentialStores::FileStore.new(path: tmp_path("credentials.json"))
    store.write("session_token" => "secret")

    store.clear

    assert_equal({}, store.read)
  end

  def test_macos_keychain_store_round_trips_json_through_security_cli
    runner = FakeShellRunner.new(
      ["security", "add-generic-password", "-U", "-a", "operator", "-s", "core-matrix-cli", "-w", "{\"session_token\":\"secret\"}"] =>
        FakeShellResult.new(success?: true, stdout: "", stderr: ""),
      ["security", "find-generic-password", "-a", "operator", "-s", "core-matrix-cli", "-w"] =>
        FakeShellResult.new(success?: true, stdout: "{\"session_token\":\"secret\"}\n", stderr: "")
    )

    store = CoreMatrixCLI::CredentialStores::MacOSKeychainStore.new(
      service: "core-matrix-cli",
      account: "operator",
      runner: runner
    )

    store.write("session_token" => "secret")

    assert_equal({ "session_token" => "secret" }, store.read)
  end

  def test_default_store_uses_file_store_when_env_requests_it
    with_env(
      "CORE_MATRIX_CLI_CREDENTIAL_STORE" => "file",
      "CORE_MATRIX_CLI_CREDENTIAL_PATH" => tmp_path("credentials-from-env.json")
    ) do
      store = CoreMatrixCLI::CredentialStore.default_store

      assert_instance_of CoreMatrixCLI::CredentialStores::FileStore, store
      assert_equal tmp_path("credentials-from-env.json"), store.path
    end
  end
end
