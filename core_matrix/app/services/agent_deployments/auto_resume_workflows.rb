module AgentDeployments
  class AutoResumeWorkflows
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:)
      @deployment = deployment
    end

    def call
      return [] unless resumable_deployment_state?

      workflow_runs_scope.filter_map do |workflow_run|
        resume_plan = auto_resume_plan_for(workflow_run.turn)

        if @deployment.eligible_for_auto_resume? && resume_plan.present?
          workflow_run if resume_workflow!(workflow_run, resume_plan)
        elsif @deployment.eligible_for_scheduling?
          escalate_to_manual_recovery!(workflow_run, drift_reason_for(workflow_run.turn))
          nil
        end
      end
    end

    private

    def workflow_runs_scope
      WorkflowRun
        .joins(:conversation)
        .includes(:turn)
        .joins(turn: :agent_deployment)
        .where(lifecycle_state: "active", wait_state: "waiting", wait_reason_kind: "agent_unavailable")
        .where(conversations: { deletion_state: "retained" })
        .where(agent_deployments: { agent_installation_id: @deployment.agent_installation_id })
        .order(:id)
    end

    def auto_resume_plan_for(turn)
      return { rebind_turn: false } if @deployment.runtime_identity_matches?(turn)
      return unless compatible_rotated_replacement?(turn)

      resolved_model_selection_snapshot = resolve_rotated_model_selection_snapshot(turn)
      return if resolved_model_selection_snapshot.blank?

      {
        rebind_turn: true,
        resolved_model_selection_snapshot: resolved_model_selection_snapshot,
      }
    end

    def resume_workflow!(workflow_run, resume_plan)
      resumed = false

      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: workflow_run,
          retained_message: "must be retained before auto resume",
          active_message: "must be active before auto resume",
          closing_message: "must not auto resume while close is in progress"
        ) do |_conversation, current_workflow_run, turn|
          next unless resumable_workflow_state?(current_workflow_run)

          rebind_turn!(turn, resume_plan) if resume_plan.fetch(:rebind_turn)
          current_workflow_run.update!(
            AgentDeployments::UnavailablePauseState.resume_attributes(
              workflow_run: current_workflow_run
            )
          )
          resumed = true
        end
      end

      resumed
    rescue ActiveRecord::RecordInvalid
      false
    end

    def escalate_to_manual_recovery!(workflow_run, drift_reason)
      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: workflow_run,
          retained_message: "must be retained before auto resume",
          active_message: "must be active before auto resume",
          closing_message: "must not auto resume while close is in progress"
        ) do |_conversation, current_workflow_run, _turn|
          next unless resumable_workflow_state?(current_workflow_run)

          current_workflow_run.update!(
            wait_reason_kind: "manual_recovery_required",
            wait_reason_payload: current_workflow_run.wait_reason_payload.merge(
              "recovery_state" => "paused_agent_unavailable",
              "drift_reason" => drift_reason,
              "reason" => @deployment.unavailability_reason.presence || current_workflow_run.wait_reason_payload["reason"]
            )
          )

          AuditLog.record!(
            installation: @deployment.installation,
            action: "agent_deployment.paused_agent_unavailable",
            subject: @deployment,
            metadata: {
              "reason" => current_workflow_run.wait_reason_payload["reason"],
              "drift_reason" => drift_reason,
              "workflow_run_ids" => [current_workflow_run.id],
            }
          )
        end
      end
    rescue ActiveRecord::RecordInvalid
      false
    end

    def resumable_deployment_state?
      @deployment.healthy? && @deployment.active_capability_snapshot.present?
    end

    def compatible_rotated_replacement?(turn)
      rotated_replacement_for?(turn) && auto_resume_target_valid?(turn)
    end

    def rotated_replacement_for?(turn)
      current_deployment = turn.agent_deployment
      current_deployment.present? &&
        current_deployment.id != @deployment.id &&
        current_deployment.same_logical_agent?(@deployment)
    end

    def resolve_rotated_model_selection_snapshot(turn)
      selector_source = turn.resolved_model_selection_snapshot["selector_source"] || "conversation"
      selector = turn.normalized_selector
      probe_turn = turn.dup
      probe_turn.installation = turn.installation
      probe_turn.conversation = turn.conversation
      probe_turn.agent_deployment = @deployment
      probe_turn.pinned_deployment_fingerprint = @deployment.fingerprint
      probe_turn.resolved_config_snapshot = turn.resolved_config_snapshot.deep_dup
      probe_turn.resolved_model_selection_snapshot = turn.resolved_model_selection_snapshot.deep_dup

      Workflows::ResolveModelSelector.call(
        turn: probe_turn,
        selector_source: selector_source,
        selector: selector
      )
    rescue ActiveRecord::RecordInvalid
      nil
    end

    def rebind_turn!(turn, resume_plan)
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: turn.conversation,
        agent_deployment: @deployment,
        record: turn,
        same_logical_agent_as: turn.agent_deployment,
        capability_contract_turn: turn
      )
      Conversations::SwitchAgentDeployment.call(
        conversation: turn.conversation,
        agent_deployment: @deployment
      )
      turn.update!(
        agent_deployment: turn.conversation.agent_deployment,
        pinned_deployment_fingerprint: turn.conversation.agent_deployment.fingerprint,
        resolved_model_selection_snapshot: resume_plan.fetch(:resolved_model_selection_snapshot)
      )
      turn.update!(
        execution_snapshot_payload: Workflows::BuildExecutionSnapshot.call(turn: turn).to_h
      )
    end

    def auto_resume_target_valid?(turn)
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: turn.conversation,
        agent_deployment: @deployment,
        record: turn.dup,
        same_logical_agent_as: turn.agent_deployment,
        capability_contract_turn: turn
      )
      true
    rescue ActiveRecord::RecordInvalid
      false
    end

    def same_execution_environment?(turn)
      turn.conversation.execution_environment_id == @deployment.execution_environment_id
    end

    def resumable_workflow_state?(workflow_run)
      workflow_run.active? &&
        workflow_run.waiting? &&
        workflow_run.wait_reason_kind == "agent_unavailable"
    end

    def drift_reason_for(turn)
      if rotated_replacement_for?(turn)
        return "execution_environment_drift" unless same_execution_environment?(turn)
        return "capability_contract_drift" unless @deployment.preserves_capability_contract?(turn)
        return "selector_resolution_drift" if resolve_rotated_model_selection_snapshot(turn).blank?
        return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

        return "deployment_rotation_drift"
      end

      return "fingerprint_drift" if @deployment.fingerprint != turn.pinned_deployment_fingerprint
      return "capability_snapshot_version_drift" if @deployment.capability_snapshot_version != turn.pinned_capability_snapshot_version
      return "auto_resume_not_permitted" unless @deployment.auto_resume_eligible?

      "runtime_drift"
    end
  end
end
