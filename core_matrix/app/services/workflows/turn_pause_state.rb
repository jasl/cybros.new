module Workflows
  module TurnPauseState
    RECOVERY_STATE_PENDING = "pause_requested".freeze
    RECOVERY_STATE_PAUSED = "paused_turn".freeze
    SNAPSHOT_KEY = WorkflowWaitSnapshot::SNAPSHOT_KEY

    module_function

    def pause_requested?(workflow_run)
      recovery_state_for(workflow_run) == RECOVERY_STATE_PENDING
    end

    def paused?(workflow_run)
      recovery_state_for(workflow_run) == RECOVERY_STATE_PAUSED
    end

    def pause_requested_attributes(workflow_run:, paused_task_run:, occurred_at:, reason:)
      {
        wait_state: "waiting",
        wait_reason_kind: "manual_recovery_required",
        wait_reason_payload: pause_payload(
          workflow_run: workflow_run,
          recovery_state: RECOVERY_STATE_PENDING,
          reason: reason,
          paused_task_run: paused_task_run
        ),
        waiting_since_at: occurred_at,
        blocking_resource_type: paused_task_run.present? ? "AgentTaskRun" : nil,
        blocking_resource_id: paused_task_run&.public_id,
      }
    end

    def paused_attributes(workflow_run:)
      {
        wait_state: "waiting",
        wait_reason_kind: "manual_recovery_required",
        wait_reason_payload: workflow_run.wait_reason_payload.deep_stringify_keys.merge(
          "recovery_state" => RECOVERY_STATE_PAUSED
        ),
        waiting_since_at: workflow_run.waiting_since_at || Time.current,
        blocking_resource_type: nil,
        blocking_resource_id: nil,
      }
    end

    def resume_attributes(workflow_run:)
      snapshot = WorkflowWaitSnapshot.from_workflow_run(workflow_run)
      return Workflows::WaitState.ready_attributes if snapshot.blank?
      return Workflows::WaitState.ready_attributes if snapshot.resolved_for?(workflow_run)

      snapshot.restore_attributes.transform_keys(&:to_sym)
    end

    def recovery_state_for(workflow_run)
      return unless workflow_run&.waiting?
      return unless workflow_run.wait_reason_kind == "manual_recovery_required"

      workflow_run.wait_reason_payload["recovery_state"]
    end

    def pause_payload(workflow_run:, recovery_state:, reason:, paused_task_run:)
      payload = {
        "recovery_state" => recovery_state,
        "reason" => reason,
      }

      if paused_task_run.present?
        payload.merge!(
          "paused_agent_task_run_id" => paused_task_run.public_id,
          "paused_workflow_node_id" => paused_task_run.workflow_node.public_id,
          "paused_logical_work_id" => paused_task_run.logical_work_id,
          "paused_attempt_no" => paused_task_run.attempt_no,
          "paused_task_kind" => paused_task_run.kind,
          "paused_task_payload" => paused_task_run.task_payload.deep_stringify_keys,
          "paused_progress_payload" => paused_task_run.progress_payload.deep_stringify_keys,
          "paused_terminal_payload" => paused_task_run.terminal_payload.deep_stringify_keys,
        )
      end

      snapshot = snapshot_for_pause(workflow_run)
      payload[SNAPSHOT_KEY] = snapshot.to_h if snapshot.present?
      payload
    end
    private_class_method :pause_payload

    def snapshot_for_pause(workflow_run)
      existing_snapshot = WorkflowWaitSnapshot.from_workflow_run(workflow_run)
      return existing_snapshot if existing_snapshot.present?

      WorkflowWaitSnapshot.capture(workflow_run)
    end
    private_class_method :snapshot_for_pause
  end
end
