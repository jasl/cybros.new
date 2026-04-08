require "test_helper"
require "erb"
require "yaml"

class TestDatabaseConfigTest < ActiveSupport::TestCase
  test "test sqlite databases are explicitly configured for solid queue worker tests" do
    config = YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true
    )
    test_config = config.fetch("test")

    assert_equal "storage/test.sqlite3", test_config.dig("primary", "database")
    assert_equal "storage/test_queue.sqlite3", test_config.dig("queue", "database")
    assert_equal ["db/queue_migrate"], Array(test_config.dig("queue", "migrations_paths"))
    assert_equal 8, test_config.dig("primary", "max_connections")
    assert_equal 16, test_config.dig("queue", "max_connections")
  end
end
