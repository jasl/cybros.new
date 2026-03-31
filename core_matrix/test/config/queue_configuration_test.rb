require "test_helper"
require "erb"
require "yaml"

class QueueConfigurationTest < ActiveSupport::TestCase
  test "queue config renders provider-specific llm workers from the runtime topology" do
    config = render_queue_yml
    workers = config.fetch("development").fetch("workers")
    queue_names = workers.map { |worker| worker.fetch("queues") }

    assert_includes queue_names, "llm_codex_subscription"
    assert_includes queue_names, "llm_openai"
    assert_includes queue_names, "llm_openrouter"
    assert_includes queue_names, "llm_dev"
    assert_includes queue_names, "llm_local"
    assert_includes queue_names, "tool_calls"
    assert_includes queue_names, "workflow_default"
    assert_includes queue_names, "maintenance"
  end

  test "provider-specific env overrides win over runtime topology defaults" do
    config = render_queue_yml(
      "SQ_THREADS_LLM_OPENAI" => "5",
      "SQ_PROCESSES_LLM_OPENAI" => "2"
    )
    openai_worker = config.fetch("development").fetch("workers").find { |worker| worker.fetch("queues") == "llm_openai" }

    assert_equal 5, openai_worker.fetch("threads")
    assert_equal 2, openai_worker.fetch("processes")
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
