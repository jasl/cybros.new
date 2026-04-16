require "test_helper"

class CoreMatrixCLIConfigStoreTest < CoreMatrixCLITestCase
  def test_read_returns_empty_hash_when_config_does_not_exist
    store = CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json"))

    assert_equal({}, store.read)
  end

  def test_write_and_read_round_trip_json_content
    store = CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json"))

    store.write(
      "base_url" => "https://core.example.com",
      "workspace_id" => "ws_123"
    )

    assert_equal(
      {
        "base_url" => "https://core.example.com",
        "workspace_id" => "ws_123",
      },
      store.read
    )
  end

  def test_merge_updates_existing_keys_without_dropping_unmentioned_values
    store = CoreMatrixCLI::ConfigStore.new(path: tmp_path("config.json"))
    store.write(
      "base_url" => "https://core.example.com",
      "workspace_id" => "ws_123"
    )

    store.merge("workspace_agent_id" => "wa_123")

    assert_equal(
      {
        "base_url" => "https://core.example.com",
        "workspace_id" => "ws_123",
        "workspace_agent_id" => "wa_123",
      },
      store.read
    )
  end

  def test_default_path_uses_env_override_when_present
    with_env("CORE_MATRIX_CLI_CONFIG_PATH" => tmp_path("env-config.json")) do
      assert_equal tmp_path("env-config.json"), CoreMatrixCLI::ConfigStore.default_path
    end
  end
end
