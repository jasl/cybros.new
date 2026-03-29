require "test_helper"

class Workflows::WithLockedWorkflowContextTest < ActiveSupport::TestCase
  test "yields the current reloaded workflow run and turn" do
    workflow_run = create_mock_turn_step_workflow_run!(resolved_config_snapshot: {})
    refreshed_at = Time.zone.parse("2026-03-29 16:00:00 UTC")
    WorkflowRun.find(workflow_run.id).update!(
      resume_metadata: { "checkpoint" => "fresh" },
      updated_at: refreshed_at
    )
    Turn.find(workflow_run.turn_id).update!(origin_payload: { "lock_state" => "fresh" })
    yielded = nil

    Workflows::WithLockedWorkflowContext.call(workflow_run: workflow_run) do |current_workflow_run, current_turn|
      yielded = [current_workflow_run, current_turn]
    end

    assert_equal workflow_run.id, yielded[0].id
    assert_equal workflow_run.turn_id, yielded[1].id
    assert_equal({ "checkpoint" => "fresh" }, yielded[0].resume_metadata)
    assert_equal({ "lock_state" => "fresh" }, yielded[1].origin_payload)
  end
end
