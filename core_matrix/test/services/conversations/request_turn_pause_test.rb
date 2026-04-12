require "test_helper"

class Conversations::RequestTurnPauseTest < ActiveSupport::TestCase
  test "requests close for mainline runtime resources and moves the workflow into pause requested without canceling the turn" do
    context = build_pause_context!

    Conversations::RequestTurnPause.call(
      turn: context[:turn],
      occurred_at: Time.zone.parse("2026-04-01 10:00:00 UTC")
    )

    assert context[:turn].reload.active?
    assert_nil context[:turn].cancellation_reason_kind

    workflow_run = context[:workflow_run].reload
    assert workflow_run.waiting?
    assert_equal "manual_recovery_required", workflow_run.wait_reason_kind
    assert_equal "pause_requested", workflow_run.recovery_state
    assert_equal "user_requested", workflow_run.recovery_reason
    assert_equal context[:agent_task_run], workflow_run.recovery_agent_task_run
    assert_equal({}, workflow_run.wait_reason_payload)
    assert_nil workflow_run.wait_snapshot_document

    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      agent_task_run: context[:agent_task_run]
    )
    assert_equal "turn_pause", close_request.payload.fetch("request_kind")
    assert_equal "turn_paused", close_request.payload.fetch("reason_kind")
    assert_equal "requested", context[:agent_task_run].reload.close_state
  end

  test "rejects pause when there is no resumable mainline agent task run" do
    context = build_agent_control_context!
    root_node = context[:workflow_run].workflow_nodes.find_by!(node_key: "root")
    root_node.update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      Conversations::RequestTurnPause.call(
        turn: context[:turn],
        occurred_at: Time.zone.parse("2026-04-01 10:00:00 UTC")
      )
    end

    assert_includes error.record.errors[:base], "must include a resumable mainline agent task run"
    assert context[:workflow_run].reload.ready?
  end

  private

  def build_pause_context!
    context = build_agent_control_context!
    root_node = context[:workflow_run].workflow_nodes.find_by!(node_key: "root")
    root_node.update!(
      lifecycle_state: "completed",
      started_at: 2.minutes.ago,
      finished_at: 1.minute.ago
    )

    agent_task_run = create_agent_task_run!(
      workflow_node: context[:workflow_node],
      lifecycle_state: "running",
      started_at: Time.current,
      logical_work_id: "pause-work-#{next_test_sequence}",
      task_payload: { "step" => "mainline" }
    )
    Leases::Acquire.call(
      leased_resource: agent_task_run,
      holder_key: context[:agent_definition_version].public_id,
      heartbeat_timeout_seconds: 30
    )

    context.merge(agent_task_run: agent_task_run)
  end
end
