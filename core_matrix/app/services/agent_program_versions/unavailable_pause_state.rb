module AgentProgramVersions
  module UnavailablePauseState
    def self.pause_attributes(workflow_run:, deployment:, recovery_state:, reason:, occurred_at:, wait_reason_kind:)
      {
        wait_state: "waiting",
        wait_reason_kind: wait_reason_kind,
        wait_reason_payload: {},
        recovery_state: recovery_state,
        recovery_reason: reason,
        recovery_drift_reason: nil,
        recovery_agent_task_run_public_id: nil,
        wait_snapshot_document: wait_snapshot_document_for_pause(workflow_run),
        waiting_since_at: occurred_at,
        blocking_resource_type: "AgentProgramVersion",
        blocking_resource_id: deployment.public_id,
      }.merge(Workflows::WaitState.cleared_detail_attributes)
    end

    def self.resume_attributes(workflow_run:)
      snapshot = WorkflowWaitSnapshot.from_workflow_run(workflow_run)
      cleared_recovery = {
        recovery_state: nil,
        recovery_reason: nil,
        recovery_drift_reason: nil,
        recovery_agent_task_run_public_id: nil,
        wait_snapshot_document: nil,
      }
      return ready_attributes.merge(cleared_recovery) if snapshot.blank?
      return ready_attributes.merge(cleared_recovery) if snapshot.resolved_for?(workflow_run)

      snapshot.restore_attributes.transform_keys(&:to_sym).merge(cleared_recovery)
    end

    def self.ready_attributes
      Workflows::WaitState.ready_attributes
    end

    def self.wait_snapshot_document_for_pause(workflow_run)
      WorkflowWaitSnapshot.document_for_pause(workflow_run)
    end
    private_class_method :wait_snapshot_document_for_pause
  end
end
