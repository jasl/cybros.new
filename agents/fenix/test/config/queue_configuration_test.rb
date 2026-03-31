require "test_helper"
require "erb"
require "yaml"

class QueueConfigurationTest < ActiveSupport::TestCase
  test "queue config renders every worker from the runtime topology" do
    config = render_queue_yml
    queue_names = config.fetch("development").fetch("workers").map { |worker| worker.fetch("queues") }

    assert_equal(
      %w[runtime_prepare_round runtime_pure_tools runtime_process_tools runtime_control maintenance],
      queue_names
    )
  end

  test "queue overrides are applied from the worker-specific environment variables" do
    config = render_queue_yml(
      "SQ_THREADS_PURE_TOOLS" => "7",
      "SQ_PROCESSES_PURE_TOOLS" => "2"
    )
    pure_tools_worker = config.fetch("development").fetch("workers").find do |worker|
      worker.fetch("queues") == "runtime_pure_tools"
    end

    assert_equal 7, pure_tools_worker.fetch("threads")
    assert_equal 2, pure_tools_worker.fetch("processes")
  end

  private

  def render_queue_yml(env_overrides = {})
    original_env = ENV.to_hash

    env_overrides.each do |key, value|
      ENV[key] = value
    end

    YAML.safe_load(
      ERB.new(Rails.root.join("config/queue.yml").read).result,
      aliases: true
    )
  ensure
    ENV.replace(original_env)
  end
end
