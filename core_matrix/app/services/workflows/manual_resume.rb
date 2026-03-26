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
        Conversations::WithMutableStateLock.call(
          conversation: @workflow_run.conversation,
          record: @workflow_run.conversation,
          retained_message: "must be retained before manual recovery",
          active_message: "must be active before manual recovery",
          closing_message: "must not resume paused work while close is in progress"
        ) do |conversation|
          validate_compatible_deployment!
          resolved_model_selection_snapshot = resolve_recovery_snapshot!
          previous_deployment = @workflow_run.turn.agent_deployment

          Conversations::SwitchAgentDeployment.call(
            conversation: conversation,
            agent_deployment: @deployment
          )
          @workflow_run.turn.update!(
            agent_deployment: @deployment,
            pinned_deployment_fingerprint: @deployment.fingerprint,
            resolved_model_selection_snapshot: resolved_model_selection_snapshot
          )
          @workflow_run.turn.update!(resolved_config_snapshot: Workflows::ContextAssembler.call(turn: @workflow_run.turn))
          @workflow_run.update!(
            AgentDeployments::UnavailablePauseState.resume_attributes(
              workflow_run: @workflow_run
            )
          )

          AuditLog.record!(
            installation: @workflow_run.installation,
            action: "workflow.manual_resumed",
            actor: @actor,
            subject: @workflow_run,
            metadata: {
              "previous_deployment_id" => previous_deployment.id,
              "deployment_id" => @deployment.id,
              "temporary_selector_override" => @selector,
            }.compact
          )

          @workflow_run
        end
      end
    end

    private

    def validate_wait_state!
      return if @workflow_run.paused_agent_unavailable?

      raise_invalid!(@workflow_run, :wait_reason_kind, "must require manual recovery before resuming")
    end

    def validate_compatible_deployment!
      raise_invalid!(@workflow_run.turn, :agent_deployment, "must be eligible for scheduling to resume paused work") unless @deployment.eligible_for_scheduling?
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: @workflow_run.conversation,
        agent_deployment: @deployment,
        record: @workflow_run.turn,
        same_logical_agent_as: @workflow_run.turn.agent_deployment,
        capability_contract_turn: @workflow_run.turn
      )
    end

    def resolve_recovery_snapshot!
      selector = @selector.presence || @workflow_run.turn.recovery_selector
      probe_turn = @workflow_run.turn.dup
      probe_turn.installation = @workflow_run.installation
      probe_turn.conversation = @workflow_run.conversation
      probe_turn.agent_deployment = @deployment
      probe_turn.pinned_deployment_fingerprint = @deployment.fingerprint
      probe_turn.resolved_config_snapshot = @workflow_run.turn.resolved_config_snapshot.deep_dup
      probe_turn.resolved_model_selection_snapshot = @workflow_run.turn.resolved_model_selection_snapshot.deep_dup

      Workflows::ResolveModelSelector.call(
        turn: probe_turn,
        selector_source: "manual_recovery",
        selector: selector
      )
    rescue ActiveRecord::RecordInvalid
      raise_invalid!(@workflow_run.turn, :resolved_model_selection_snapshot, "must remain resolvable for the recovery action")
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
