module Workflows
  class ManualResume
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, deployment:, actor:, selector: nil)
      @workflow_run = workflow_run
      @deployment = deployment
      @actor = actor
      @selector = selector
    end

    def call
      validate_wait_state!

      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: @workflow_run,
          retained_message: "must be retained before manual recovery",
          active_message: "must be active before manual recovery",
          closing_message: "must not resume paused work while close is in progress"
        ) do |conversation, workflow_run, turn|
          validate_wait_state!(workflow_run)
          recovery_target = AgentProgramVersions::ResolveRecoveryTarget.call(
            conversation: workflow_run.conversation,
            turn: turn,
            agent_program_version: @deployment,
            selector_source: "manual_recovery",
            selector: @selector.presence || turn.recovery_selector,
            rebind_turn: true
          )
          previous_deployment = turn.agent_program_version

          AgentProgramVersions::RebindTurn.call(
            turn: turn,
            recovery_target: recovery_target
          )
          workflow_run.update!(
            AgentProgramVersions::UnavailablePauseState.resume_attributes(
              workflow_run: workflow_run
            )
          )

          AuditLog.record!(
            installation: workflow_run.installation,
            action: "workflow.manual_resumed",
            actor: @actor,
            subject: workflow_run,
            metadata: {
              "previous_deployment_id" => previous_deployment.id,
              "deployment_id" => recovery_target.agent_program_version.id,
              "temporary_selector_override" => @selector,
            }.compact
          )

          workflow_run
        end
      end
    end

    private

    def validate_wait_state!(workflow_run = @workflow_run)
      return if workflow_run.paused_agent_unavailable?

      raise_invalid!(workflow_run, :wait_reason_kind, "must require manual recovery before resuming")
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
