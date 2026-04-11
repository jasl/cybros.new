module AgentSnapshots
  class BuildRecoveryPlan
    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, workflow_run:)
      @agent_snapshot = agent_snapshot
      @workflow_run = workflow_run
      @turn = workflow_run.turn
    end

    def call
      return resume_plan if runtime_identity_matches? && @agent_snapshot.auto_resume_eligible?
      return manual_plan("auto_resume_not_permitted") if runtime_identity_matches?

      return rotated_replacement_plan if rotated_replacement?

      manual_plan(drift_reason_for_current_binding)
    end

    private

    def resume_plan
      AgentSnapshotRecoveryPlan.new(action: "resume")
    end

    def manual_plan(drift_reason)
      AgentSnapshotRecoveryPlan.new(
        action: "manual_recovery_required",
        drift_reason: drift_reason
      )
    end

    def rotated_replacement_plan
      recovery_target = AgentSnapshots::ResolveRecoveryTarget.call(
        conversation: @turn.conversation,
        turn: @turn,
        agent_snapshot: @agent_snapshot,
        record: @turn.dup,
        selector_source: recovery_selector_source,
        selector: @turn.recovery_selector,
        require_auto_resume_eligible: true,
        rebind_turn: true
      )

      AgentSnapshotRecoveryPlan.new(
        action: "resume_with_rebind",
        recovery_target: recovery_target
      )
    rescue AgentSnapshots::ResolveRecoveryTarget::Invalid => error
      manual_plan(error.reason)
    end

    def runtime_identity_matches?
      @agent_snapshot.runtime_identity_matches?(@turn)
    end

    def rotated_replacement?
      current_agent_snapshot = @turn.agent_snapshot
      current_agent_snapshot.present? &&
        current_agent_snapshot.id != @agent_snapshot.id &&
        current_agent_snapshot.same_logical_agent?(@agent_snapshot)
    end

    def drift_reason_for_current_binding
      return "fingerprint_drift" if @agent_snapshot.fingerprint != @turn.pinned_agent_snapshot_fingerprint
      return "capability_contract_drift" if @agent_snapshot.capability_snapshot_version != @turn.pinned_capability_snapshot_version
      return "auto_resume_not_permitted" unless @agent_snapshot.auto_resume_eligible?

      "runtime_drift"
    end

    def recovery_selector_source
      @turn.resolved_model_selection_snapshot["selector_source"] || "conversation"
    end
  end
end
