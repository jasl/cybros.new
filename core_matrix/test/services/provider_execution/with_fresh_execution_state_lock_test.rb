require "test_helper"

class ProviderExecution::WithFreshExecutionStateLockTest < ActiveSupport::TestCase
  test "yields reloaded workflow state while execution remains fresh" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    refreshed_at = Time.zone.parse("2026-03-29 14:00:00 UTC")
    WorkflowRun.find(workflow_run.id).update!(
      resume_metadata: { "checkpoint" => "refreshed", "refreshed_at" => refreshed_at.iso8601 }
    )
    WorkflowNode.find(workflow_node.id).update!(metadata: { "lock_version" => "fresh" })
    Turn.find(workflow_run.turn.id).update!(origin_payload: { "lock_state" => "fresh" })
    yielded = nil

    ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: workflow_node) do |current_node, current_run, current_turn|
      yielded = [current_node, current_run, current_turn]
    end

    assert_equal workflow_node.id, yielded[0].id
    assert_equal workflow_run.id, yielded[1].id
    assert_equal workflow_run.turn.id, yielded[2].id
    assert_equal({ "lock_version" => "fresh" }, yielded[0].metadata)
    assert_equal(
      { "checkpoint" => "refreshed", "refreshed_at" => refreshed_at.iso8601 },
      yielded[1].resume_metadata
    )
    assert_equal({ "lock_state" => "fresh" }, yielded[2].origin_payload)
  end

  test "raises stale when the latest workflow node status is terminal" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    workflow_node = workflow_run.workflow_nodes.find_by!(node_key: "turn_step")
    WorkflowNodeEvent.create!(
      installation: workflow_run.installation,
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      ordinal: 0,
      event_kind: "status",
      payload: { "state" => "completed" }
    )

    error = assert_raises(ProviderExecution::WithFreshExecutionStateLock::StaleExecutionError) do
      ProviderExecution::WithFreshExecutionStateLock.call(workflow_node: workflow_node) { flunk("expected stale lock rejection") }
    end

    assert_equal "provider execution result is stale", error.message
  end
end
