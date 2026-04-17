require "test_helper"

class ConfigRepositoryTest < CoreMatrixCLITestCase
  def test_read_returns_empty_hash_when_config_does_not_exist
    repo = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))

    assert_equal({}, repo.read)
  end

  def test_merge_round_trips_stringified_json_keys
    repo = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))

    repo.merge(workspace_id: "ws_123", nested: { current_agent_id: "wa_123" })

    assert_equal(
      { "workspace_id" => "ws_123", "nested" => { "current_agent_id" => "wa_123" } },
      repo.read
    )
  end

  def test_write_and_clear_round_trip_json_content
    repo = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))

    repo.write(base_url: "https://core.example.com", workspace_id: "ws_123")

    assert_equal(
      {
        "base_url" => "https://core.example.com",
        "workspace_id" => "ws_123",
      },
      repo.read
    )

    repo.clear

    assert_equal({}, repo.read)
  end

  def test_merge_preserves_existing_keys
    repo = CoreMatrixCLI::State::ConfigRepository.new(path: tmp_path("config.json"))
    repo.write(base_url: "https://core.example.com", workspace_id: "ws_123")

    repo.merge(workspace_agent_id: "wa_123")

    assert_equal(
      {
        "base_url" => "https://core.example.com",
        "workspace_id" => "ws_123",
        "workspace_agent_id" => "wa_123",
      },
      repo.read
    )
  end

  def test_default_path_uses_env_override_when_present
    with_env("CORE_MATRIX_CLI_CONFIG_PATH" => tmp_path("env-config.json")) do
      assert_equal tmp_path("env-config.json"), CoreMatrixCLI::State::ConfigRepository.default_path
    end
  end

  def test_default_path_uses_home_config_directory_without_override
    with_env("CORE_MATRIX_CLI_CONFIG_PATH" => nil) do
      with_dir_home("/tmp/core-matrix-cli-home") do
        assert_equal(
          "/tmp/core-matrix-cli-home/.config/core_matrix_cli/config.json",
          CoreMatrixCLI::State::ConfigRepository.default_path
        )
      end
    end
  end
end
