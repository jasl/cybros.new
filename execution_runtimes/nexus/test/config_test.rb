require "test_helper"

class ConfigTest < Minitest::Test
  def test_defaults_home_root_under_user_home
    config = CybrosNexus::Config.load(env: {}, home_dir: "/tmp/cybros-home")

    assert_equal "/tmp/cybros-home/.nexus", config.home_root
    assert_equal File.join(config.home_root, "state.sqlite3"), config.state_path
    assert_equal "127.0.0.1", config.http_bind
    assert_equal 4040, config.http_port
  end
end
