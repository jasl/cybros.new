require "minitest/autorun"
require_relative "../lib/monorepo_dev_environment"

class MonorepoDevEnvironmentTest < Minitest::Test
  def test_defaults_include_core_and_agent_ports
    env = MonorepoDevEnvironment.defaults({})

    assert_equal "3000", env.fetch("PORT")
    assert_equal "3000", env.fetch("CORE_MATRIX_PORT")
    assert_equal "36173", env.fetch("AGENT_FENIX_PORT")
    assert_equal "http://127.0.0.1:36173", env.fetch("AGENT_FENIX_BASE_URL")
  end

  def test_base_url_tracks_overridden_agent_fenix_port
    env = MonorepoDevEnvironment.defaults("AGENT_FENIX_PORT" => "41234")

    assert_equal "41234", env.fetch("AGENT_FENIX_PORT")
    assert_equal "http://127.0.0.1:41234", env.fetch("AGENT_FENIX_BASE_URL")
  end

  def test_explicit_base_url_is_preserved
    env = MonorepoDevEnvironment.defaults(
      "AGENT_FENIX_PORT" => "41234",
      "AGENT_FENIX_BASE_URL" => "http://127.0.0.1:49999"
    )

    assert_equal "http://127.0.0.1:49999", env.fetch("AGENT_FENIX_BASE_URL")
  end
end
