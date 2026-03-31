require "test_helper"
require "erb"
require "yaml"

class DatabaseConfigurationTest < ActiveSupport::TestCase
  test "default database pool tracks the widest solid queue worker pool" do
    config = render_database_yml

    assert_equal 8, config.dig("development", "primary", "max_connections")
    assert_equal 8, config.dig("development", "queue", "max_connections")
    assert_equal 8, config.dig("production", "primary", "max_connections")
    assert_equal 8, config.dig("production", "queue", "max_connections")
  end

  test "fenix db pool override wins over the computed default" do
    config = render_database_yml("FENIX_DB_POOL" => "12")

    assert_equal 12, config.dig("development", "primary", "max_connections")
    assert_equal 12, config.dig("development", "queue", "max_connections")
  end

  test "higher queue thread counts raise the computed database pool default" do
    config = render_database_yml("SQ_THREADS_PURE_TOOLS" => "8")

    assert_equal 10, config.dig("development", "primary", "max_connections")
    assert_equal 10, config.dig("development", "queue", "max_connections")
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
