require "test_helper"
require "erb"
require "yaml"

class TestDatabaseConfigTest < ActiveSupport::TestCase
  test "test sqlite databases are explicitly configured for solid queue worker tests" do
    config = render_database_yml
    test_config = config.fetch("test")

    assert_equal "storage/test.sqlite3", test_config.dig("primary", "database")
    assert_equal "storage/test_queue.sqlite3", test_config.dig("queue", "database")
    assert_equal ["db/queue_migrate"], Array(test_config.dig("queue", "migrations_paths"))
    assert_equal 8, test_config.dig("primary", "max_connections")
    assert_equal 16, test_config.dig("queue", "max_connections")
  end

  test "test sqlite databases can be rooted under an explicit nexus storage directory" do
    config = render_database_yml("NEXUS_STORAGE_ROOT" => "/tmp/nexus-slot/storage")
    test_config = config.fetch("test")

    assert_equal "/tmp/nexus-slot/storage/test.sqlite3", test_config.dig("primary", "database")
    assert_equal "/tmp/nexus-slot/storage/test_queue.sqlite3", test_config.dig("queue", "database")
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
