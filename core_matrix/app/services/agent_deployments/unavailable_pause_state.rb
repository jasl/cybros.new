module AgentDeployments
  module UnavailablePauseState
    SNAPSHOT_KEY = "paused_wait_snapshot".freeze

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
      snapshot = paused_wait_snapshot(workflow_run)
      return ready_attributes if snapshot.blank?
      return ready_attributes if snapshot_resolved?(workflow_run, snapshot)

      {
        wait_state: "waiting",
        wait_reason_kind: snapshot["wait_reason_kind"],
        wait_reason_payload: (snapshot["wait_reason_payload"] || {}).deep_stringify_keys,
        waiting_since_at: parse_waiting_since(snapshot["waiting_since_at"]),
        blocking_resource_type: snapshot["blocking_resource_type"],
        blocking_resource_id: snapshot["blocking_resource_id"],
      }
    end

    def self.paused_wait_snapshot(workflow_run)
      snapshot = workflow_run.wait_reason_payload[SNAPSHOT_KEY]
      return if snapshot.blank?

      snapshot.deep_stringify_keys
    end

    def self.ready_attributes
      {
        wait_state: "ready",
        wait_reason_kind: nil,
        wait_reason_payload: {},
        waiting_since_at: nil,
        blocking_resource_type: nil,
        blocking_resource_id: nil,
      }
    end

    def self.pause_payload(workflow_run:, recovery_state:, reason:)
      payload = {
        "recovery_state" => recovery_state,
        "reason" => reason,
        "pinned_deployment_fingerprint" => workflow_run.turn.pinned_deployment_fingerprint,
        "pinned_capability_version" => workflow_run.turn.pinned_capability_snapshot_version,
      }

      snapshot = snapshot_for_pause(workflow_run)
      payload[SNAPSHOT_KEY] = snapshot if snapshot.present?
      payload
    end
    private_class_method :pause_payload

    def self.snapshot_for_pause(workflow_run)
      existing_snapshot = paused_wait_snapshot(workflow_run)
      return existing_snapshot if existing_snapshot.present?
      return unless workflow_run.waiting?
      return if workflow_run.wait_reason_kind.in?(%w[agent_unavailable manual_recovery_required])

      {
        "wait_reason_kind" => workflow_run.wait_reason_kind,
        "wait_reason_payload" => workflow_run.wait_reason_payload.deep_stringify_keys,
        "waiting_since_at" => workflow_run.waiting_since_at&.iso8601,
        "blocking_resource_type" => workflow_run.blocking_resource_type,
        "blocking_resource_id" => workflow_run.blocking_resource_id,
      }
    end
    private_class_method :snapshot_for_pause

    def self.snapshot_resolved?(workflow_run, snapshot)
      wait_reason_kind = snapshot["wait_reason_kind"].presence
      return true if wait_reason_kind.blank?

      case wait_reason_kind
      when "human_interaction"
        HumanInteractionRequest.where(
          workflow_run: workflow_run,
          public_id: snapshot["blocking_resource_id"],
          lifecycle_state: "open",
          blocking: true
        ).none?
      when "retryable_failure"
        AgentTaskRun.where(
          workflow_run: workflow_run,
          public_id: snapshot["blocking_resource_id"],
          lifecycle_state: "failed"
        ).none?
      when "policy_gate"
        queued_turn_id = snapshot.dig("wait_reason_payload", "queued_turn_id")
        return true if queued_turn_id.blank?

        Turn.where(
          conversation: workflow_run.conversation,
          public_id: queued_turn_id,
          lifecycle_state: "queued"
        ).none?
      else
        false
      end
    end
    private_class_method :snapshot_resolved?

    def self.parse_waiting_since(value)
      return if value.blank?

      Time.zone.parse(value)
    end
    private_class_method :parse_waiting_since
  end
end
