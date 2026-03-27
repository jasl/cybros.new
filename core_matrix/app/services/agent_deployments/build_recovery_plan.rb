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
      return manual_plan("execution_environment_drift") unless same_execution_environment?
      return manual_plan("capability_contract_drift") unless @deployment.preserves_capability_contract?(@turn)
      return manual_plan("auto_resume_not_permitted") unless @deployment.auto_resume_eligible?

      resolved_snapshot = resolve_rotated_model_selection_snapshot
      return manual_plan("selector_resolution_drift") if resolved_snapshot.blank?

      AgentDeploymentRecoveryPlan.new(
        action: "resume_with_rebind",
        resolved_model_selection_snapshot: resolved_snapshot.merge(
          "deployment_fingerprint" => @deployment.fingerprint
        )
      )
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

    def same_execution_environment?
      @turn.conversation.execution_environment_id == @deployment.execution_environment_id
    end

    def drift_reason_for_current_binding
      return "fingerprint_drift" if @deployment.fingerprint != @turn.pinned_deployment_fingerprint
      return "capability_snapshot_version_drift" if @deployment.capability_snapshot_version != @turn.pinned_capability_snapshot_version
      return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

      "runtime_drift"
    end

    def resolve_rotated_model_selection_snapshot
      selector_source = @turn.resolved_model_selection_snapshot["selector_source"] || "conversation"
      selector = @turn.normalized_selector
      probe_turn = @turn.dup
      probe_turn.installation = @turn.installation
      probe_turn.conversation = @turn.conversation
      probe_turn.agent_deployment = probe_deployment
      probe_turn.pinned_deployment_fingerprint = @deployment.fingerprint
      probe_turn.resolved_config_snapshot = @turn.resolved_config_snapshot.deep_dup
      probe_turn.resolved_model_selection_snapshot = @turn.resolved_model_selection_snapshot.deep_dup

      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: @turn.conversation,
        agent_deployment: @deployment,
        record: probe_turn,
        same_logical_agent_as: @turn.agent_deployment,
        capability_contract_turn: @turn
      )

      Workflows::ResolveModelSelector.call(
        turn: probe_turn,
        selector_source: selector_source,
        selector: selector
      )
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def probe_deployment
      @probe_deployment ||= @deployment.dup.tap do |deployment|
        deployment.active_capability_snapshot = @deployment.active_capability_snapshot
        deployment.define_singleton_method(:eligible_for_scheduling?) { true }
      end
    end
  end
end
