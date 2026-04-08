require "test_helper"

class Workflows::ResumeBlockedStepTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "requeues a blocked workflow node and clears workflow wait state" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "waiting", started_at: 1.minute.ago, finished_at: nil)
    workflow_run.turn.update!(lifecycle_state: "waiting")
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_reason_payload: {},
      wait_failure_kind: "provider_rate_limited",
      wait_retry_scope: "step",
      wait_retry_strategy: "automatic",
      wait_attempt_no: 1,
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: workflow_node.public_id
    )

    assert_enqueued_with(
      job: Workflows::ExecuteNodeJob,
      args: ->(job_args) do
        job_args.first == workflow_node.public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:queue_name] == "llm_dev" &&
          Time.iso8601(job_args.second.fetch(:enqueued_at_iso8601)).is_a?(Time)
      rescue ArgumentError, KeyError
        false
      end
    ) do
      Workflows::ResumeBlockedStep.call(workflow_run: workflow_run)
    end

    assert_equal "queued", workflow_node.reload.lifecycle_state
    assert_nil workflow_node.finished_at
    assert_equal "active", workflow_run.turn.reload.lifecycle_state
    assert_equal "ready", workflow_run.reload.wait_state
    assert_nil workflow_run.wait_reason_kind
  end

  test "rejects resume when the turn has been interrupted" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "waiting", started_at: 1.minute.ago, finished_at: nil)
    workflow_run.turn.update!(
      lifecycle_state: "waiting",
      cancellation_requested_at: Time.current,
      cancellation_reason_kind: "turn_interrupted"
    )
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_reason_payload: {},
      wait_failure_kind: "provider_rate_limited",
      wait_retry_scope: "step",
      wait_retry_strategy: "automatic",
      wait_attempt_no: 1,
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: workflow_node.public_id
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Workflows::ResumeBlockedStep.call(workflow_run: workflow_run)
    end

    assert_includes error.record.errors[:cancellation_reason_kind], "must not be fenced by turn interrupt"
  end
end
