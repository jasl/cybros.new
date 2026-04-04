require "test_helper"

class Workflows::BlockNodeForFailureTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "moves a workflow node turn and run into external dependency waiting" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    result = nil
    assert_enqueued_with(job: Workflows::ResumeBlockedStepJob, args: [workflow_run.public_id]) do
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
    assert_equal "provider_rate_limited", workflow_run.wait_reason_payload["failure_kind"]
    assert_equal "automatic", workflow_run.wait_reason_payload["retry_strategy"]
    assert_equal 1, workflow_run.wait_reason_payload["attempt_no"]
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
      metadata: {
        "blocked_retry_state" => {
          "failure_kind" => "provider_rate_limited",
          "attempt_no" => 2,
        },
      }
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
    assert_equal 3, workflow_run.reload.wait_reason_payload["attempt_no"]
    assert_equal "manual", workflow_run.wait_reason_payload["retry_strategy"]
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
    assert_equal "manual", workflow_run.wait_reason_payload["retry_strategy"]
    assert_equal "provider_auth_expired", workflow_run.wait_reason_payload["failure_kind"]
  end

  test "enqueues automatic resume for retryable contract failures" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "running", started_at: Time.current)

    assert_enqueued_with(job: Workflows::ResumeBlockedStepJob, args: [workflow_run.public_id]) do
      result = Workflows::BlockNodeForFailure.call(
        workflow_node: workflow_node,
        failure_category: "contract_error",
        failure_kind: "invalid_program_response_contract",
        retry_strategy: "automatic",
        max_auto_retries: 1,
        last_error_summary: "program response is invalid"
      )

      refute result.terminal?
    end

    assert_equal "retryable_failure", workflow_run.reload.wait_reason_kind
    assert_equal "automatic", workflow_run.wait_reason_payload["retry_strategy"]
    assert_equal "invalid_program_response_contract", workflow_run.wait_reason_payload["failure_kind"]
  end
end
