require "test_helper"
require "erb"
require "yaml"

class QueueConfigurationTest < ActiveSupport::TestCase
  test "queue config renders the runtime worker queues explicitly" do
    config = render_queue_yml
    queue_names = config.fetch("development").fetch("workers").map { |worker| worker.fetch("queues") }

    assert_equal %w[runtime_control maintenance], queue_names
  end

  test "default worker threads match the 8 core runtime baseline" do
    workers = render_queue_yml.fetch("development").fetch("workers").index_by { |worker| worker.fetch("queues") }

    assert_equal 8, workers.fetch("runtime_control").fetch("threads")
    assert_equal 1, workers.fetch("runtime_control").fetch("processes")
    assert_equal 1, workers.fetch("maintenance").fetch("threads")
    assert_equal 1, workers.fetch("maintenance").fetch("processes")
  end

  test "queue overrides are applied from the runtime control environment variables" do
    config = render_queue_yml(
      "SQ_THREADS_RUNTIME_CONTROL" => "6",
      "SQ_PROCESSES_RUNTIME_CONTROL" => "2"
    )
    runtime_control = config.fetch("development").fetch("workers").find do |worker|
      worker.fetch("queues") == "runtime_control"
    end

    assert_equal 6, runtime_control.fetch("threads")
    assert_equal 2, runtime_control.fetch("processes")
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
