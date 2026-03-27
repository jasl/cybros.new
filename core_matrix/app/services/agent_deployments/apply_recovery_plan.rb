module AgentDeployments
  class ApplyRecoveryPlan
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, workflow_run:, recovery_plan:)
      @deployment = deployment
      @workflow_run = workflow_run
      @recovery_plan = recovery_plan
    end

    def call
      applied = false

      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: @workflow_run,
          retained_message: "must be retained before auto resume",
          active_message: "must be active before auto resume",
          closing_message: "must not auto resume while close is in progress"
        ) do |_conversation, current_workflow_run, turn|
          next unless resumable_workflow_state?(current_workflow_run)

          if @recovery_plan.resume?
            rebind_turn!(turn) if @recovery_plan.rebind_turn?
            current_workflow_run.update!(
              AgentDeployments::UnavailablePauseState.resume_attributes(
                workflow_run: current_workflow_run
              )
            )
            applied = true
            next
          end

          current_workflow_run.update!(
            wait_reason_kind: "manual_recovery_required",
            wait_reason_payload: current_workflow_run.wait_reason_payload.merge(
              "recovery_state" => "paused_agent_unavailable",
              "drift_reason" => @recovery_plan.drift_reason,
              "reason" => @deployment.unavailability_reason.presence || current_workflow_run.wait_reason_payload["reason"]
            )
          )

          AuditLog.record!(
            installation: @deployment.installation,
            action: "agent_deployment.paused_agent_unavailable",
            subject: @deployment,
            metadata: {
              "reason" => current_workflow_run.wait_reason_payload["reason"],
              "drift_reason" => @recovery_plan.drift_reason,
              "workflow_run_ids" => [current_workflow_run.id],
            }
          )
        end
      end

      applied
    rescue ActiveRecord::RecordInvalid
      false
    end

    private

    def rebind_turn!(turn)
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
        resolved_model_selection_snapshot: @recovery_plan.resolved_model_selection_snapshot
      )
      turn.update!(
        execution_snapshot_payload: Workflows::BuildExecutionSnapshot.call(turn: turn).to_h
      )
    end

    def resumable_workflow_state?(workflow_run)
      workflow_run.active? &&
        workflow_run.waiting? &&
        workflow_run.wait_reason_kind == "agent_unavailable"
    end
  end
end
