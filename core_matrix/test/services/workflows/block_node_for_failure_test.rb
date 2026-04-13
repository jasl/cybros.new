require "test_helper"

class Workflows::BlockNodeForFailureTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "moves a workflow node turn and run into external dependency waiting" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    result = nil
    assert_enqueued_with(
      job: Workflows::ResumeBlockedStepJob,
      queue: "workflow_resume",
      args: ->(job_args) do
        job_args.first == workflow_run.public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:expected_waiting_since_at_iso8601] == workflow_run.reload.waiting_since_at&.utc&.iso8601(6)
      end
    ) do
      result = Workflows::BlockNodeForFailure.call(
        workflow_node: workflow_node,
        failure_category: "external_dependency_blocked",
        failure_kind: "provider_rate_limited",
        retry_strategy: "automatic",
        max_auto_retries: 2,
        next_retry_at: 2.minutes.from_now,
        last_error_summary: "provider is rate limited"
      )
    end

    assert_equal "waiting", workflow_node.reload.lifecycle_state
    assert_equal "waiting", workflow_run.turn.reload.lifecycle_state
    assert_equal "waiting", workflow_run.reload.wait_state
    assert_equal "external_dependency_blocked", workflow_run.wait_reason_kind
    assert_equal "WorkflowNode", workflow_run.blocking_resource_type
    assert_equal workflow_node.public_id, workflow_run.blocking_resource_id
    assert_equal "provider_rate_limited", workflow_run.wait_failure_kind
    assert_equal "step", workflow_run.wait_retry_scope
    assert_equal "automatic", workflow_run.wait_retry_strategy
    assert_equal 1, workflow_run.wait_attempt_no
    assert_equal 2, workflow_run.wait_max_auto_retries
    assert workflow_run.wait_next_retry_at.present?
    assert_equal "provider is rate limited", workflow_run.wait_last_error_summary
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_equal({}, workflow_run.workflow_run_wait_detail.wait_reason_payload)
    assert_equal "provider_rate_limited", workflow_node.reload.blocked_retry_failure_kind
    assert_equal 1, workflow_node.blocked_retry_attempt_no
    refute result.terminal?
  end

  test "marks implementation failures terminally" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    result = Workflows::BlockNodeForFailure.call(
      workflow_node: workflow_node,
      failure_category: "implementation_error",
      failure_kind: "internal_unexpected_error",
      last_error_summary: "boom"
    )

    assert result.terminal?
    assert_equal "failed", workflow_node.reload.lifecycle_state
    assert_equal "failed", workflow_run.turn.reload.lifecycle_state
    assert_equal "failed", workflow_run.reload.lifecycle_state
    assert workflow_run.ready?
  end

  test "downgrades automatic retry to manual after the retry limit is exceeded" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(
      lifecycle_state: "running",
      started_at: Time.current,
      blocked_retry_failure_kind: "provider_rate_limited",
      blocked_retry_attempt_no: 2
    )

    result = Workflows::BlockNodeForFailure.call(
      workflow_node: workflow_node,
      failure_category: "external_dependency_blocked",
      failure_kind: "provider_rate_limited",
      retry_strategy: "automatic",
      max_auto_retries: 2,
      next_retry_at: 2.minutes.from_now,
      last_error_summary: "provider is rate limited"
    )

    refute result.terminal?
    assert_equal "manual", result.retry_strategy
    assert_nil result.next_retry_at
    assert_equal 3, workflow_run.reload.wait_attempt_no
    assert_equal "manual", workflow_run.wait_retry_strategy
  end

  test "does not enqueue automatic resume for manual external dependency blocks" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    assert_no_enqueued_jobs only: Workflows::ResumeBlockedStepJob do
      result = Workflows::BlockNodeForFailure.call(
        workflow_node: workflow_node,
        failure_category: "external_dependency_blocked",
        failure_kind: "provider_auth_expired",
        retry_strategy: "manual",
        max_auto_retries: 0,
        last_error_summary: "provider auth expired"
      )

      refute result.terminal?
    end

    assert_equal "external_dependency_blocked", workflow_run.reload.wait_reason_kind
    assert_equal "manual", workflow_run.wait_retry_strategy
    assert_equal "provider_auth_expired", workflow_run.wait_failure_kind
  end

  test "enqueues automatic resume for retryable contract failures" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    assert_enqueued_with(
      job: Workflows::ResumeBlockedStepJob,
      queue: "workflow_resume",
      args: ->(job_args) do
        job_args.first == workflow_run.public_id &&
          job_args.second.is_a?(Hash) &&
          job_args.second[:expected_waiting_since_at_iso8601] == workflow_run.reload.waiting_since_at&.utc&.iso8601(6)
      end
    ) do
      result = Workflows::BlockNodeForFailure.call(
        workflow_node: workflow_node,
        failure_category: "contract_error",
        failure_kind: "invalid_agent_response_contract",
        retry_strategy: "automatic",
        max_auto_retries: 1,
        last_error_summary: "agent response is invalid"
      )

      refute result.terminal?
    end

    assert_equal "retryable_failure", workflow_run.reload.wait_reason_kind
    assert_equal "automatic", workflow_run.wait_retry_strategy
    assert_equal "invalid_agent_response_contract", workflow_run.wait_failure_kind
  end
end
