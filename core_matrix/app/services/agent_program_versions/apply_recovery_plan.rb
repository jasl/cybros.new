module AgentProgramVersions
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
            AgentProgramVersions::RebindTurn.call(
              turn: turn,
              recovery_target: @recovery_plan.recovery_target
            ) if @recovery_plan.rebind_turn?
            current_workflow_run.update!(
              AgentProgramVersions::UnavailablePauseState.resume_attributes(
                workflow_run: current_workflow_run
              )
            )
            applied = true
            next
          end

          current_workflow_run.update!(
            Workflows::WaitState.cleared_detail_attributes.merge(
              wait_reason_kind: "manual_recovery_required",
              wait_reason_payload: {},
              recovery_state: "paused_agent_unavailable",
              recovery_reason: @deployment.unavailability_reason.presence || current_workflow_run.recovery_reason,
              recovery_drift_reason: @recovery_plan.drift_reason
            )
          )

          AuditLog.record!(
            installation: @deployment.installation,
            action: "agent_program_version.paused_agent_unavailable",
            subject: @deployment,
            metadata: {
              "reason" => current_workflow_run.recovery_reason,
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

    def resumable_workflow_state?(workflow_run)
      workflow_run.active? &&
        workflow_run.waiting? &&
        workflow_run.wait_reason_kind == "agent_unavailable"
    end
  end
end
