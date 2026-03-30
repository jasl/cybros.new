require "test_helper"
require "yaml"

class DistributionContractTest < ActionDispatch::IntegrationTest
  test "README, pairing manifest, and compose sample describe the same distribution contract" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    readme = Rails.root.join("README.md").read
    compose_path = Rails.root.join("docker-compose.fenix.yml")
    dockerfile = Rails.root.join("Dockerfile").read
    database_config = Rails.root.join("config/database.yml").read
    proxy_script = Rails.root.join("bin/fenix-dev-proxy").read
    entrypoint = Rails.root.join("bin/docker-entrypoint").read

    assert compose_path.exist?, "expected docker-compose.fenix.yml to exist"

    compose = YAML.safe_load(compose_path.read)
    fenix_service = compose.fetch("services").fetch("fenix")
    proxy_service = compose.fetch("services").fetch("fenix-dev-proxy")
    environment_entries = Array(fenix_service.fetch("environment"))
    proxy_environment_entries = Array(proxy_service.fetch("environment"))

    assert_match(/Docker Compose/i, readme)
    assert_match(/Ubuntu 24\.04/i, readme)
    assert_match(/macOS/i, readme)
    assert_match(/FENIX_DEV_PROXY_PORT/, readme)
    assert_match(/workspace.*memory.*command_run.*process_run.*browser_session/im, readme)
    assert_match(/operator_surface_smoke\.rb/, readme)
    assert_match(/FROM base AS ruby-runtime/, dockerfile)
    assert_match(/cache\.ruby-lang\.org/, dockerfile)
    assert_match(/setpriv --reuid/, entrypoint)
    assert_match(/HOME=.*LOGNAME=/, entrypoint)
    assert_match(/database: storage\/production\.sqlite3/, database_config)
    assert_match(/fenix dev proxy routes/, proxy_script)

    assert_equal "ubuntu-24.04", body.dig("environment_capability_payload", "runtime_foundation", "base_image")
    assert_equal "FENIX_DEV_PROXY_PORT", body.dig("environment_plane", "capability_payload", "fixed_port_dev_proxy", "external_port_env")

    assert_equal ".", fenix_service.fetch("build")
    assert_equal ".", proxy_service.fetch("build")
    assert environment_entries.any? { |entry| entry.start_with?("SECRET_KEY_BASE=") }
    assert environment_entries.any? { |entry| entry.start_with?("FENIX_PUBLIC_BASE_URL=") }
    assert environment_entries.any? { |entry| entry.start_with?("FENIX_DEV_PROXY_PORT=") }
    assert environment_entries.any? { |entry| entry.start_with?("PLAYWRIGHT_BROWSERS_PATH=") }
    assert_includes Array(fenix_service.fetch("volumes")), "fenix_storage:/rails/storage"
    assert proxy_environment_entries.any? { |entry| entry.start_with?("FENIX_DEV_PROXY_PORT=") }
    assert_includes Array(fenix_service.fetch("volumes")), "./tmp/docker-workspace:/workspace"
    assert_includes Array(proxy_service.fetch("volumes")), "./tmp/docker-workspace:/workspace"
    assert_includes compose.fetch("volumes").keys, "fenix_storage"
  end
end
