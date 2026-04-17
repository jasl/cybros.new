require "test_helper"
require_relative "../support/fake_shell_runner"

class CredentialRepositoryTest < CoreMatrixCLITestCase
  class RecordingStore
    attr_reader :writes, :cleared

    def initialize(read_value = {})
      @read_value = read_value
      @writes = []
      @cleared = false
    end

    def read
      @read_value
    end

    def write(values)
      @writes << values
      @read_value = values
    end

    def clear
      @cleared = true
      @read_value = {}
    end
  end

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
      store = CoreMatrixCLI::State::CredentialRepository.default_store

      assert_instance_of CoreMatrixCLI::CredentialStores::FileStore, store
      assert_equal tmp_path("credentials-from-env.json"), store.path
    end
  end

  def test_credential_repository_delegates_to_selected_store
    store = RecordingStore.new("session_token" => "stored")
    repository = CoreMatrixCLI::State::CredentialRepository.new(store: store)

    assert_equal({ "session_token" => "stored" }, repository.read)

    repository.write("session_token" => "new-secret")
    repository.clear

    assert_equal [{ "session_token" => "new-secret" }], store.writes
    assert_equal true, store.cleared
  end

  def test_file_store_default_path_uses_home_config_directory_without_override
    with_env("CORE_MATRIX_CLI_CREDENTIAL_PATH" => nil) do
      with_dir_home("/tmp/core-matrix-cli-home") do
        assert_equal(
          "/tmp/core-matrix-cli-home/.config/core_matrix_cli/credentials.json",
          CoreMatrixCLI::CredentialStores::FileStore.default_path
        )
      end
    end
  end

  def test_default_store_falls_back_to_file_store_with_default_path_when_keychain_is_unavailable
    with_env(
      "CORE_MATRIX_CLI_CREDENTIAL_STORE" => nil,
      "CORE_MATRIX_CLI_CREDENTIAL_PATH" => nil
    ) do
      with_dir_home("/tmp/core-matrix-cli-home") do
        with_stubbed_singleton_method(
          CoreMatrixCLI::CredentialStores::MacOSKeychainStore,
          :available?,
          -> { false }
        ) do
          store = CoreMatrixCLI::State::CredentialRepository.default_store

          assert_instance_of CoreMatrixCLI::CredentialStores::FileStore, store
          assert_equal "/tmp/core-matrix-cli-home/.config/core_matrix_cli/credentials.json", store.path
        end
      end
    end
  end
end
