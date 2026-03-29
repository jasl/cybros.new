module AgentDeployments
  module UnavailablePauseState
    SNAPSHOT_KEY = WorkflowWaitSnapshot::SNAPSHOT_KEY

    def self.pause_attributes(workflow_run:, deployment:, recovery_state:, reason:, occurred_at:, wait_reason_kind:)
      {
        wait_state: "waiting",
        wait_reason_kind: wait_reason_kind,
        wait_reason_payload: pause_payload(
          workflow_run: workflow_run,
          recovery_state: recovery_state,
          reason: reason
        ),
        waiting_since_at: occurred_at,
        blocking_resource_type: "AgentDeployment",
        blocking_resource_id: deployment.public_id,
      }
    end

    def self.resume_attributes(workflow_run:)
      snapshot = WorkflowWaitSnapshot.from_workflow_run(workflow_run)
      return ready_attributes if snapshot.blank?
      return ready_attributes if snapshot.resolved_for?(workflow_run)

      snapshot.restore_attributes.transform_keys(&:to_sym)
    end

    def self.ready_attributes
      Workflows::WaitState.ready_attributes
    end

    def self.pause_payload(workflow_run:, recovery_state:, reason:)
      payload = {
        "recovery_state" => recovery_state,
        "reason" => reason,
        "pinned_deployment_fingerprint" => workflow_run.turn.pinned_deployment_fingerprint,
        "pinned_capability_version" => workflow_run.turn.pinned_capability_snapshot_version,
      }

      snapshot = snapshot_for_pause(workflow_run)
      payload[SNAPSHOT_KEY] = snapshot.to_h if snapshot.present?
      payload
    end
    private_class_method :pause_payload

    def self.snapshot_for_pause(workflow_run)
      existing_snapshot = WorkflowWaitSnapshot.from_workflow_run(workflow_run)
      return existing_snapshot if existing_snapshot.present?

      WorkflowWaitSnapshot.capture(workflow_run)
    end
    private_class_method :snapshot_for_pause
  end
end
