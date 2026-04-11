module Workflows
  class ManualResume
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_run:, agent_snapshot:, actor:, selector: nil, conversation_control_request: nil)
      @workflow_run = workflow_run
      @agent_snapshot = agent_snapshot
      @actor = actor
      @selector = selector
      @conversation_control_request = conversation_control_request
    end

    def call
      validate_wait_state!

      resumed_workflow_run = ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: @workflow_run,
          retained_message: "must be retained before manual recovery",
          active_message: "must be active before manual recovery",
          closing_message: "must not resume paused work while close is in progress"
        ) do |conversation, workflow_run, turn|
          validate_wait_state!(workflow_run)
          recovery_target = AgentSnapshots::ResolveRecoveryTarget.call(
            conversation: workflow_run.conversation,
            turn: turn,
            agent_snapshot: @agent_snapshot,
            selector_source: "manual_recovery",
            selector: @selector.presence || turn.recovery_selector,
            rebind_turn: true
          )
          previous_agent_snapshot = turn.agent_snapshot

          AgentSnapshots::RebindTurn.call(
            turn: turn,
            recovery_target: recovery_target
          )
          workflow_run.update!(
            AgentSnapshots::UnavailablePauseState.resume_attributes(
              workflow_run: workflow_run
            )
          )

          AuditLog.record!(
            installation: workflow_run.installation,
            action: "workflow.manual_resumed",
            actor: @actor,
            subject: workflow_run,
            metadata: {
              "previous_agent_snapshot_id" => previous_agent_snapshot.id,
              "agent_snapshot_id" => recovery_target.agent_snapshot.id,
              "temporary_selector_override" => @selector,
            }.compact
          )

          workflow_run
        end
      end

      complete_control_request!(resumed_workflow_run)
      resumed_workflow_run
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

    def complete_control_request!(workflow_run)
      return if @conversation_control_request.blank?

      @conversation_control_request.update!(
        lifecycle_state: "completed",
        completed_at: Time.current,
        result_payload: @conversation_control_request.result_payload.merge(
          "workflow_run_id" => workflow_run.public_id,
          "conversation_id" => workflow_run.conversation.public_id
        )
      )
    end
  end
end
