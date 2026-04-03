require "test_helper"

class Workflows::ResumeBlockedStepJobTest < ActiveJob::TestCase
  test "resumes a waiting workflow node when the run is still blocked" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    workflow_node.update!(lifecycle_state: "waiting", started_at: 1.minute.ago, finished_at: nil)
    workflow_run.turn.update!(lifecycle_state: "waiting")
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "external_dependency_blocked",
      wait_reason_payload: {
        "failure_kind" => "provider_rate_limited",
        "retry_scope" => "step",
        "retry_strategy" => "automatic",
      },
      waiting_since_at: Time.current,
      blocking_resource_type: "WorkflowNode",
      blocking_resource_id: workflow_node.public_id
    )

    assert_enqueued_with(job: Workflows::ExecuteNodeJob, args: [workflow_node.public_id]) do
      Workflows::ResumeBlockedStepJob.perform_now(workflow_run.public_id)
    end

    assert_equal "queued", workflow_node.reload.lifecycle_state
    assert_equal "ready", workflow_run.reload.wait_state
  end

  test "does nothing once the workflow is no longer blocked" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})

    assert_no_enqueued_jobs only: Workflows::ExecuteNodeJob do
      Workflows::ResumeBlockedStepJob.perform_now(workflow_run.public_id)
    end
  end
end
