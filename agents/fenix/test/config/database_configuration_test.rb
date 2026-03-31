require "test_helper"
require "erb"
require "yaml"

class DatabaseConfigurationTest < ActiveSupport::TestCase
  test "default database pools come from the runtime topology" do
    config = render_database_yml

    assert_equal 5, config.dig("development", "primary", "max_connections")
    assert_equal 8, config.dig("development", "queue", "max_connections")
    assert_equal 5, config.dig("production", "primary", "max_connections")
    assert_equal 8, config.dig("production", "queue", "max_connections")
  end

  test "explicit pool overrides apply independently" do
    config = render_database_yml(
      "FENIX_PRIMARY_DB_POOL" => "12",
      "FENIX_QUEUE_DB_POOL" => "16"
    )

    assert_equal 12, config.dig("development", "primary", "max_connections")
    assert_equal 16, config.dig("development", "queue", "max_connections")
  end

  test "test environment keeps split primary and queue databases" do
    config = render_database_yml

    assert_equal "storage/test.sqlite3", config.dig("test", "primary", "database")
    assert_equal "storage/queue_test.sqlite3", config.dig("test", "queue", "database")
  end

  private

  def render_database_yml(env_overrides = {})
    original_env = ENV.to_hash

    env_overrides.each do |key, value|
      ENV[key] = value
    end

    YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true
    )
  ensure
    ENV.replace(original_env)
  end
end
