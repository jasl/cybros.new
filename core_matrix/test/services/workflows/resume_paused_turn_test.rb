require "test_helper"

class Workflows::ResumePausedTurnTest < ActiveSupport::TestCase
  test "resume creates a new same-turn attempt with a resume delivery kind" do
    context = build_paused_turn_context!

    resumed = Workflows::ResumePausedTurn.call(
      workflow_run: context[:workflow_run],
      occurred_at: Time.zone.parse("2026-04-01 10:30:00 UTC")
    )

    assert_equal context[:workflow_run].id, resumed.id
    assert resumed.ready?

    new_task = AgentTaskRun.where(
      workflow_run: resumed,
      logical_work_id: context[:agent_task_run].logical_work_id,
      attempt_no: 2
    ).sole

    assert_equal context[:turn], new_task.turn
    assert_equal context[:workflow_node], new_task.workflow_node
    assert_equal "queued", new_task.lifecycle_state
    assert_equal "turn_resume", new_task.task_payload["delivery_kind"]
    assert_equal 1, new_task.task_payload["previous_attempt_no"]
    assert_equal context[:agent_task_run].public_id, new_task.task_payload["paused_agent_task_run_id"]

    assignment = AgentControlMailboxItem.find_by!(agent_task_run: new_task)
    assert_equal "execution_assignment", assignment.item_type
  end

  test "retry creates a new same-turn attempt with an explicit paused-retry delivery kind" do
    context = build_paused_turn_context!

    retried = Workflows::RetryPausedTurn.call(
      workflow_run: context[:workflow_run],
      occurred_at: Time.zone.parse("2026-04-01 10:45:00 UTC")
    )

    assert_equal context[:workflow_run].id, retried.id
    assert retried.ready?

    new_task = AgentTaskRun.where(
      workflow_run: retried,
      logical_work_id: context[:agent_task_run].logical_work_id,
      attempt_no: 2
    ).sole

    assert_equal "paused_retry", new_task.task_payload["delivery_kind"]
    assert_equal 1, new_task.task_payload["previous_attempt_no"]
    assert_equal context[:agent_task_run].public_id, new_task.task_payload["paused_agent_task_run_id"]
  end

  test "resume rebuilds the execution snapshot from paused steering input" do
    context = build_paused_turn_context!

    Turns::SteerCurrentInput.call(
      turn: context[:turn].reload,
      content: "Paused steering input",
      expected_turn_id: context[:turn].public_id
    )

    resumed = Workflows::ResumePausedTurn.call(
      workflow_run: context[:workflow_run],
      occurred_at: Time.zone.parse("2026-04-01 10:30:00 UTC")
    )

    assert_equal "Paused steering input", resumed.turn.reload.selected_input_message.content
    assert_equal "Paused steering input",
      resumed.turn.execution_snapshot.to_h
        .fetch("conversation_projection")
        .fetch("messages")
        .last
        .fetch("content")
    assert_equal resumed.turn.selected_input_message.public_id,
      resumed.turn.execution_snapshot.to_h
        .fetch("task")
        .fetch("selected_input_message_id")
  end

  private

  def build_paused_turn_context!
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
      holder_key: context[:deployment].public_id,
      heartbeat_timeout_seconds: 30
    )

    occurred_at = Time.zone.parse("2026-04-01 10:20:00 UTC")
    Conversations::RequestTurnPause.call(turn: context[:turn], occurred_at: occurred_at)
    close_request = AgentControlMailboxItem.find_by!(
      item_type: "resource_close_request",
      agent_task_run: agent_task_run
    )
    AgentControl::ApplyCloseOutcome.call(
      resource: agent_task_run,
      mailbox_item: close_request,
      close_state: "closed",
      close_outcome_kind: "graceful",
      close_outcome_payload: { "source" => "test" },
      occurred_at: occurred_at + 5.seconds
    )

    context.merge(agent_task_run: agent_task_run.reload, close_request: close_request.reload)
  end
end
