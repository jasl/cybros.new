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

  def test_default_path_uses_env_override_when_present
    with_env("CORE_MATRIX_CLI_CONFIG_PATH" => tmp_path("env-config.json")) do
      assert_equal tmp_path("env-config.json"), CoreMatrixCLI::State::ConfigRepository.default_path
    end
  end
end
