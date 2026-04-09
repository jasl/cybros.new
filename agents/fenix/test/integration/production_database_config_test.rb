require "test_helper"
require "erb"
require "yaml"

class ProductionDatabaseConfigTest < ActiveSupport::TestCase
  test "production sqlite databases are explicitly configured for docker boot" do
    config = render_database_yml
    production = config.fetch("production")

    assert_equal "storage/production.sqlite3", production.dig("primary", "database")
    assert_equal "storage/production_cache.sqlite3", production.dig("cache", "database")
    assert_equal "storage/production_queue.sqlite3", production.dig("queue", "database")
    assert_equal 8, production.dig("primary", "max_connections")
    assert_equal 16, production.dig("queue", "max_connections")
  end

  test "production sqlite databases can be rooted under an explicit fenix storage directory" do
    config = render_database_yml("FENIX_STORAGE_ROOT" => "/tmp/fenix-slot/storage")
    production = config.fetch("production")

    assert_equal "/tmp/fenix-slot/storage/production.sqlite3", production.dig("primary", "database")
    assert_equal "/tmp/fenix-slot/storage/production_cache.sqlite3", production.dig("cache", "database")
    assert_equal "/tmp/fenix-slot/storage/production_queue.sqlite3", production.dig("queue", "database")
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
