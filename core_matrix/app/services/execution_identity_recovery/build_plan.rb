module ExecutionIdentityRecovery
  class BuildPlan
    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, workflow_run:)
      @agent_definition_version = agent_definition_version
      @workflow_run = workflow_run
      @turn = workflow_run.turn
    end

    def call
      return resume_plan if execution_identity_matches? && @agent_definition_version.auto_resume_eligible?
      return manual_plan("auto_resume_not_permitted") if execution_identity_matches?
      return rotated_replacement_plan if rotated_replacement?

      manual_plan(drift_reason_for_current_binding)
    end

    private

    def resume_plan
      ExecutionIdentityRecoveryPlan.new(action: "resume")
    end

    def manual_plan(drift_reason)
      ExecutionIdentityRecoveryPlan.new(
        action: "manual_recovery_required",
        drift_reason: drift_reason
      )
    end

    def rotated_replacement_plan
      recovery_target = ExecutionIdentityRecovery::ResolveTarget.call(
        conversation: @turn.conversation,
        turn: @turn,
        agent_definition_version: @agent_definition_version,
        record: @turn.dup,
        selector_source: recovery_selector_source,
        selector: @turn.recovery_selector,
        require_auto_resume_eligible: true,
        rebind_turn: true
      )

      ExecutionIdentityRecoveryPlan.new(
        action: "resume_with_rebind",
        recovery_target: recovery_target
      )
    rescue ExecutionIdentityRecovery::ResolveTarget::Invalid => error
      manual_plan(error.reason)
    end

    def execution_identity_matches?
      @turn.agent_definition_version_id == @agent_definition_version.id &&
        @agent_definition_version.runtime_identity_matches?(@turn)
    end

    def rotated_replacement?
      current_agent_definition_version = @turn.agent_definition_version
      current_agent_definition_version.present? &&
        current_agent_definition_version.id != @agent_definition_version.id &&
        current_agent_definition_version.same_logical_agent?(@agent_definition_version)
    end

    def drift_reason_for_current_binding
      return "fingerprint_drift" if @agent_definition_version.definition_fingerprint != @turn.pinned_agent_definition_fingerprint
      return "capability_contract_drift" unless @agent_definition_version.preserves_capability_contract?(@turn)
      return "auto_resume_not_permitted" unless @agent_definition_version.auto_resume_eligible?

      "runtime_drift"
    end

    def recovery_selector_source
      @turn.resolved_model_selection_snapshot["selector_source"] || "conversation"
    end
  end
end
