require "test_helper"
require "erb"
require "yaml"

class DevelopmentDatabaseConfigTest < ActiveSupport::TestCase
  test "development sqlite databases are explicitly configured for solid queue boot" do
    config = render_database_yml
    development = config.fetch("development")

    assert_equal "storage/development.sqlite3", development.dig("primary", "database")
    assert_equal "storage/development_queue.sqlite3", development.dig("queue", "database")
    assert_equal ["db/queue_migrate"], Array(development.dig("queue", "migrations_paths"))
    assert_equal 8, development.dig("primary", "max_connections")
    assert_equal 16, development.dig("queue", "max_connections")
  end

  test "development sqlite databases can be rooted under an explicit nexus storage directory" do
    config = render_database_yml("NEXUS_STORAGE_ROOT" => "/tmp/nexus-slot/storage")
    development = config.fetch("development")

    assert_equal "/tmp/nexus-slot/storage/development.sqlite3", development.dig("primary", "database")
    assert_equal "/tmp/nexus-slot/storage/development_queue.sqlite3", development.dig("queue", "database")
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
