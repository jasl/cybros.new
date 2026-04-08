require "test_helper"
require "erb"
require "yaml"

class ProductionDatabaseConfigTest < ActiveSupport::TestCase
  test "production sqlite databases are explicitly configured for docker boot" do
    config = YAML.safe_load(
      ERB.new(Rails.root.join("config/database.yml").read).result,
      aliases: true
    )
    production = config.fetch("production")

    assert_equal "storage/production.sqlite3", production.dig("primary", "database")
    assert_equal "storage/production_cache.sqlite3", production.dig("cache", "database")
    assert_equal "storage/production_queue.sqlite3", production.dig("queue", "database")
  end
end
