module Workflows
  module TurnPauseState
    RECOVERY_STATE_PENDING = "pause_requested".freeze
    RECOVERY_STATE_PAUSED = "paused_turn".freeze

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
        wait_reason_payload: {},
        recovery_state: RECOVERY_STATE_PENDING,
        recovery_reason: reason,
        recovery_drift_reason: nil,
        recovery_agent_task_run_public_id: paused_task_run&.public_id,
        wait_snapshot_document: wait_snapshot_document_for_pause(workflow_run),
        waiting_since_at: occurred_at,
        blocking_resource_type: paused_task_run.present? ? "AgentTaskRun" : nil,
        blocking_resource_id: paused_task_run&.public_id,
      }
    end

    def paused_attributes(workflow_run:)
      {
        wait_state: "waiting",
        wait_reason_kind: "manual_recovery_required",
        wait_reason_payload: workflow_run.wait_reason_payload.deep_stringify_keys,
        recovery_state: RECOVERY_STATE_PAUSED,
        recovery_reason: workflow_run.recovery_reason,
        recovery_drift_reason: workflow_run.recovery_drift_reason,
        recovery_agent_task_run_public_id: workflow_run.recovery_agent_task_run_public_id,
        wait_snapshot_document: workflow_run.wait_snapshot_document,
        waiting_since_at: workflow_run.waiting_since_at || Time.current,
        blocking_resource_type: nil,
        blocking_resource_id: nil,
      }
    end

    def resume_attributes(workflow_run:)
      snapshot = WorkflowWaitSnapshot.from_workflow_run(workflow_run)
      cleared_recovery = {
        recovery_state: nil,
        recovery_reason: nil,
        recovery_drift_reason: nil,
        recovery_agent_task_run_public_id: nil,
        wait_snapshot_document: nil,
      }
      return Workflows::WaitState.ready_attributes.merge(cleared_recovery) if snapshot.blank?
      return Workflows::WaitState.ready_attributes.merge(cleared_recovery) if snapshot.resolved_for?(workflow_run)

      snapshot.restore_attributes.transform_keys(&:to_sym).merge(cleared_recovery)
    end

    def recovery_state_for(workflow_run)
      return unless workflow_run&.waiting?
      return unless workflow_run.wait_reason_kind == "manual_recovery_required"

      workflow_run.recovery_state
    end

    def wait_snapshot_document_for_pause(workflow_run)
      WorkflowWaitSnapshot.document_for_pause(workflow_run)
    end
    private_class_method :wait_snapshot_document_for_pause
  end
end
