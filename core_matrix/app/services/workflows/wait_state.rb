module Workflows
  module WaitState
    DETAIL_ATTRIBUTE_NAMES = %i[
      wait_policy_mode
      wait_retry_scope
      wait_resume_mode
      wait_failure_kind
      wait_retry_strategy
      wait_attempt_no
      wait_max_auto_retries
      wait_next_retry_at
      wait_last_error_summary
    ].freeze

    def self.cleared_detail_attributes
      DETAIL_ATTRIBUTE_NAMES.index_with { nil }
    end

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
      }.merge(cleared_detail_attributes)
    end
  end
end
