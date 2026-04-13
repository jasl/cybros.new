require "test_helper"
require "erb"
require "yaml"

class DataRetentionConfigurationTest < ActiveSupport::TestCase
  test "recurring config schedules data retention maintenance on the maintenance queue" do
    config = YAML.safe_load(
      ERB.new(Rails.root.join("config/recurring.yml").read).result,
      aliases: true
    )

    task = config.fetch("production").fetch("data_retention_maintenance")

    assert_equal "DataRetention::RunMaintenanceJob", task.fetch("class")
    assert_equal "maintenance", task.fetch("queue")
    assert_includes task.fetch("schedule"), "every day"
  end

  test "recurring config schedules workflow bootstrap backlog recovery on the maintenance queue" do
    config = YAML.safe_load(
      ERB.new(Rails.root.join("config/recurring.yml").read).result,
      aliases: true
    )

    task = config.fetch("production").fetch("workflow_bootstrap_backlog_recovery")

    assert_equal "Turns::RecoverWorkflowBootstrapBacklogJob", task.fetch("class")
    assert_equal "maintenance", task.fetch("queue")
    assert_equal "every 5 minutes", task.fetch("schedule")
  end

  test "env sample documents the retention knobs" do
    env_sample = Rails.root.join("env.sample").read

    assert_includes env_sample, "Optional: Data Retention"
    assert_includes env_sample, "# DATA_RETENTION_BATCH_SIZE=500"
    assert_includes env_sample, "# DATA_RETENTION_BOUNDED_AUDIT_DAYS=30"
    assert_includes env_sample, "# DATA_RETENTION_SUPERVISION_CLOSED_DAYS=7"
  end
end
