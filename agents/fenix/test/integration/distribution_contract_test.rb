require "test_helper"
require "yaml"

class DistributionContractTest < ActionDispatch::IntegrationTest
  test "README, pairing manifest, and compose sample describe the same distribution contract" do
    get "/runtime/manifest"

    assert_response :success

    body = JSON.parse(response.body)
    readme = Rails.root.join("README.md").read
    env_sample = Rails.root.join("env.sample").read
    compose_path = Rails.root.join("docker-compose.fenix.yml")
    dockerfile = Rails.root.join("Dockerfile").read
    database_config = Rails.root.join("config/database.yml").read
    proxy_script = Rails.root.join("bin/fenix-dev-proxy").read
    runtime_worker = Rails.root.join("bin/runtime-worker").read
    entrypoint = Rails.root.join("bin/docker-entrypoint").read
    bootstrap_script = Rails.root.join("scripts/bootstrap-runtime-deps.sh").read

    assert compose_path.exist?, "expected docker-compose.fenix.yml to exist"

    compose = YAML.safe_load(compose_path.read)
    fenix_service = compose.fetch("services").fetch("fenix")
    proxy_service = compose.fetch("services").fetch("fenix-dev-proxy")
    environment_entries = Array(fenix_service.fetch("environment"))
    proxy_environment_entries = Array(proxy_service.fetch("environment"))

    assert_match(/Docker Compose/i, readme)
    assert_match(/Ubuntu 24\.04/i, readme)
    assert_match(/macOS/i, readme)
    assert_match(/Rails\.app\.creds/, readme)
    assert_match(/docker run --env-file/i, readme)
    assert_match(/credentials:edit/, readme)
    assert_match(/FENIX_DEV_PROXY_PORT/, readme)
    assert_match(/workspace.*memory.*command_run.*process_run.*browser_session/im, readme)
    assert_match(/operator_surface_smoke\.rb/, readme)
    assert_match(/default_config_snapshot\.model_slots\.summary/, readme)
    assert_match(/FROM base AS ruby-runtime/, dockerfile)
    assert_match(/cache\.ruby-lang\.org/, dockerfile)
    refute_match(/RAILS_MASTER_KEY/, dockerfile)
    assert_match(/setpriv --reuid/, entrypoint)
    assert_match(/HOME=.*LOGNAME=/, entrypoint)
    assert_match(/database: storage\/production\.sqlite3/, database_config)
    assert_match(/fenix dev proxy routes/, proxy_script)
    assert_match(/STANDALONE_SOLID_QUEUE/, runtime_worker)
    assert_match(/runtime:control_loop_forever/, runtime_worker)
    assert_match(/FENIX_NODE_VERSION:-22\./, bootstrap_script)
    assert_match(%r{https://nodejs\.org/dist/}, bootstrap_script)
    assert_match(%r{https://registry\.npmjs\.org/npm/-/npm-}, bootstrap_script)
    assert_match(/FENIX_RUNTIME_BOOTSTRAP_STAMP/, bootstrap_script)
    assert_match(/runtime dependencies already satisfied/, bootstrap_script)
    assert_match(/npm-cli\.js/, bootstrap_script)
    assert_match(/npm install --global pnpm/, bootstrap_script)
    refute_match(/deb\.nodesource\.com/, bootstrap_script)

    assert_match(/docker run --env-file/i, env_sample)
    assert_match(/bin\/rails credentials:edit/, env_sample)
    assert_match(/CORE_MATRIX_BASE_URL=/, env_sample)
    assert_match(/CORE_MATRIX_MACHINE_CREDENTIAL=/, env_sample)
    refute_match(/Provider LLM queues/i, env_sample)

    assert_equal "ubuntu-24.04", body.dig("execution_capability_payload", "runtime_foundation", "base_image")
    assert_equal "FENIX_DEV_PROXY_PORT", body.dig("execution_plane", "capability_payload", "fixed_port_dev_proxy", "external_port_env")

    assert_equal ".", fenix_service.fetch("build")
    assert_equal ".", proxy_service.fetch("build")
    assert_equal ["./.env"], Array(fenix_service.fetch("env_file"))
    assert_equal ["./.env"], Array(proxy_service.fetch("env_file"))
    refute environment_entries.any? { |entry| entry.start_with?("SECRET_KEY_BASE=") }
    refute environment_entries.any? { |entry| entry.start_with?("CORE_MATRIX_BASE_URL=") }
    refute environment_entries.any? { |entry| entry.start_with?("CORE_MATRIX_MACHINE_CREDENTIAL=") }
    assert_equal ["RAILS_ENV=production"], environment_entries
    assert_includes Array(fenix_service.fetch("volumes")), "fenix_storage:/rails/storage"
    assert_equal ["RAILS_ENV=production"], proxy_environment_entries
    assert_includes Array(fenix_service.fetch("volumes")), "./tmp/docker-workspace:/workspace"
    assert_includes Array(proxy_service.fetch("volumes")), "./tmp/docker-workspace:/workspace"
    assert_includes compose.fetch("volumes").keys, "fenix_storage"
  end
end
