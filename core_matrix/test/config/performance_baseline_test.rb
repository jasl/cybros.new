require "test_helper"
require "erb"
require "yaml"
require "active_support/core_ext/enumerable"

class PerformanceBaselineTest < ActiveSupport::TestCase
  PumaConfigProbe = Struct.new(:thread_value, :worker_value, keyword_init: true) do
    def threads(value)
      self.thread_value = value
    end

    def workers(value)
      self.worker_value = value
    end

    def port(*) = nil
    def plugin(*) = nil
    def pidfile(*) = nil
  end

  test "puma defaults target the 8 fenix web baseline" do
    probe = evaluate_puma_config(rails_env: "development")

    assert_equal 8, probe.thread_value
    assert_equal 0, probe.worker_value
  end

  test "puma defaults stay at the 8 fenix web baseline in production" do
    probe = evaluate_puma_config(rails_env: "production")

    assert_equal 8, probe.thread_value
    assert_equal 2, probe.worker_value
  end

  test "primary pool baseline does not collapse when threads are set explicitly" do
    config = render_database_yml("RAILS_MAX_THREADS" => "8")

    assert_equal 16, config.fetch("development").fetch("primary").fetch("pool")
  end

  test "queue pool baseline covers the widened queue topology" do
    config = render_database_yml("RAILS_MAX_THREADS" => "8")
    queue_thread_budget = render_queue_yml.fetch("development").fetch("workers").sum do |worker|
      worker.fetch("threads") * worker.fetch("processes")
    end

    assert_operator config.fetch("development").fetch("queue").fetch("pool"), :>=, queue_thread_budget
  end

  test "database pool baseline scales with threads above the floor" do
    config = render_database_yml("RAILS_MAX_THREADS" => "24")

    assert_equal 24, config.fetch("development").fetch("primary").fetch("pool")
  end

  test "global database pool override still wins over every role baseline" do
    config = render_database_yml(
      "RAILS_MAX_THREADS" => "8",
      "RAILS_DB_POOL" => "24"
    )

    assert_equal 24, config.fetch("development").fetch("primary").fetch("pool")
    assert_equal 24, config.fetch("development").fetch("queue").fetch("pool")
    assert_equal 24, config.fetch("development").fetch("cable").fetch("pool")
  end

  test "queue-specific pool override still wins over the widened baseline" do
    config = render_database_yml(
      "RAILS_MAX_THREADS" => "8",
      "RAILS_QUEUE_DB_POOL" => "48"
    )

    assert_equal 48, config.fetch("development").fetch("queue").fetch("pool")
  end

  test "env sample documents the 8 fenix concurrency baseline" do
    env_sample = Rails.root.join("env.sample").read

    assert_includes env_sample, "Optional: Performance Tuning"
    assert_includes env_sample, "# RAILS_MAX_THREADS=8"
    assert_includes env_sample, "# RAILS_WEB_CONCURRENCY=2"
    assert_includes env_sample, "# RAILS_DB_POOL=40"
    assert_includes env_sample, "# RAILS_PRIMARY_DB_POOL=16"
    assert_includes env_sample, "# RAILS_QUEUE_DB_POOL=40"
    assert_includes env_sample, "# RAILS_CABLE_DB_POOL=16"
    assert_includes env_sample, "Optional: Solid Queue Reference Topology (8 CPU"
    assert_includes env_sample, "# SQ_THREADS_LLM_CODEX_SUBSCRIPTION=4"
    assert_includes env_sample, "# SQ_THREADS_LLM_OPENAI=6"
    assert_includes env_sample, "# SQ_THREADS_LLM_OPENROUTER=4"
    assert_includes env_sample, "# SQ_THREADS_LLM_DEV=2"
    assert_includes env_sample, "# SQ_THREADS_LLM_LOCAL=2"
    assert_includes env_sample, "# SQ_THREADS_TOOL_CALLS=12"
    assert_includes env_sample, "# SQ_THREADS_WORKFLOW_DEFAULT=6"
    assert_not_includes env_sample, "Optional: Fenix Runtime Baseline"
    assert_not_includes env_sample, "# FENIX_PRIMARY_DB_POOL=8"
    assert_not_includes env_sample, "# FENIX_QUEUE_DB_POOL=16"
    assert_not_includes env_sample, "# SQ_THREADS_RUNTIME_CONTROL=8"
    assert_includes env_sample, "intended to coordinate up to"
    assert_includes env_sample, "eight connected Fenix runtimes"
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

  def evaluate_puma_config(rails_env:)
    probe = PumaConfigProbe.new
    probe_class = Class.new do
      const_set(:Rails, Struct.new(:env).new(ActiveSupport::StringInquirer.new(rails_env)))
    end
    context = probe_class.new

    context.define_singleton_method(:threads) { |value| probe.thread_value = value }
    context.define_singleton_method(:workers) { |value| probe.worker_value = value }
    context.define_singleton_method(:port) { |*| nil }
    context.define_singleton_method(:plugin) { |*| nil }
    context.define_singleton_method(:pidfile) { |*| nil }

    context.instance_eval(Rails.root.join("config/puma.rb").read, "config/puma.rb")

    probe
  end
end
