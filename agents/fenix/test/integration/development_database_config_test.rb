require "test_helper"
require "erb"
require "yaml"

class DevelopmentDatabaseConfigTest < ActiveSupport::TestCase
  test "development sqlite databases are explicitly configured for solid queue boot" do
    config = YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true
    )
    development = config.fetch("development")

    assert_equal "storage/development.sqlite3", development.dig("primary", "database")
    assert_equal "storage/development_queue.sqlite3", development.dig("queue", "database")
    assert_equal ["db/queue_migrate"], Array(development.dig("queue", "migrations_paths"))
  end
end
