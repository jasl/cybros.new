module Workflows
  module WaitState
    def self.ready_attributes
      {
        wait_state: "ready",
        wait_reason_kind: nil,
        wait_reason_payload: {},
        recovery_state: nil,
        recovery_reason: nil,
        recovery_drift_reason: nil,
        recovery_agent_task_run_public_id: nil,
        wait_snapshot_document: nil,
        waiting_since_at: nil,
        blocking_resource_type: nil,
        blocking_resource_id: nil,
      }
    end
  end
end
