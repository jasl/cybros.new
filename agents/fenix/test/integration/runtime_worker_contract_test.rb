require "test_helper"

class RuntimeWorkerContractTest < ActiveSupport::TestCase
  test "runtime worker and puma agree on the standalone solid queue contract" do
    runtime_worker = Rails.root.join("bin/runtime-worker").read
    jobs = Rails.root.join("bin/jobs").read
    rails = Rails.root.join("bin/rails").read
    env_sample = Rails.root.join("env.sample").read
    puma_config = Rails.root.join("config/puma.rb").read
    runtime_tasks = Rails.root.join("lib/tasks/runtime.rake").read

    assert_match(/STANDALONE_SOLID_QUEUE/, runtime_worker)
    assert_match(%r{\./bin/jobs start &}, runtime_worker)
    assert_match(/exec \.\/bin\/rails runtime:control_loop_forever/, runtime_worker)
    refute_match(/PythonBootstrap\.ensure_ready!/, jobs)
    refute_match(/PythonBootstrap\.ensure_ready!/, rails)
    refute Rails.root.join("bin/fenix-dev-proxy").exist?
    refute Rails.root.join("config/caddy/Caddyfile").exist?
    refute_match(/FENIX_DEV_PROXY_PORT=/, env_sample)
    refute_match(/FENIX_DEV_PROXY_ROUTES_FILE=/, env_sample)
    refute_match(/FENIX_HOME_ROOT=/, env_sample)
    assert_match(/ENV\["STANDALONE_SOLID_QUEUE"\]/, puma_config)
    assert_match(/task control_loop_forever: :environment/, runtime_tasks)
    assert_match(/task pair_with_core_matrix: :environment/, runtime_tasks)
  end
end
