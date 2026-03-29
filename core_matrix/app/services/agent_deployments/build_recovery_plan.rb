module AgentDeployments
  class BuildRecoveryPlan
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, workflow_run:)
      @deployment = deployment
      @workflow_run = workflow_run
      @turn = workflow_run.turn
    end

    def call
      return resume_plan if runtime_identity_matches? && @deployment.auto_resume_eligible?
      return manual_plan("auto_resume_not_permitted") if runtime_identity_matches?

      return rotated_replacement_plan if rotated_replacement?

      manual_plan(drift_reason_for_current_binding)
    end

    private

    def resume_plan
      AgentDeploymentRecoveryPlan.new(action: "resume")
    end

    def manual_plan(drift_reason)
      AgentDeploymentRecoveryPlan.new(
        action: "manual_recovery_required",
        drift_reason: drift_reason
      )
    end

    def rotated_replacement_plan
      recovery_target = AgentDeployments::ResolveRecoveryTarget.call(
        conversation: @turn.conversation,
        turn: @turn,
        agent_deployment: @deployment,
        record: @turn.dup,
        selector_source: recovery_selector_source,
        selector: @turn.recovery_selector,
        require_auto_resume_eligible: true,
        rebind_turn: true
      )

      AgentDeploymentRecoveryPlan.new(
        action: "resume_with_rebind",
        recovery_target: recovery_target
      )
    rescue AgentDeployments::ResolveRecoveryTarget::Invalid => error
      manual_plan(error.reason)
    end

    def runtime_identity_matches?
      @deployment.runtime_identity_matches?(@turn)
    end

    def rotated_replacement?
      current_deployment = @turn.agent_deployment
      current_deployment.present? &&
        current_deployment.id != @deployment.id &&
        current_deployment.same_logical_agent?(@deployment)
    end

    def drift_reason_for_current_binding
      return "fingerprint_drift" if @deployment.fingerprint != @turn.pinned_deployment_fingerprint
      return "capability_snapshot_version_drift" if @deployment.capability_snapshot_version != @turn.pinned_capability_snapshot_version
      return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

      "runtime_drift"
    end

    def recovery_selector_source
      @turn.resolved_model_selection_snapshot["selector_source"] || "conversation"
    end
  end
end
