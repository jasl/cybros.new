module Workflows
  class ManualRetry
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
      validate_retry_state!
      validate_retry_target!

      root_node = @workflow_run.workflow_nodes.order(:ordinal).first
      raise_invalid!(@workflow_run, :workflow_nodes, "must include a root node to retry") if root_node.blank?

      ApplicationRecord.transaction do
        @workflow_run.update!(lifecycle_state: "canceled")
        @workflow_run.turn.update!(lifecycle_state: "canceled")

        retried_turn = Turns::StartUserTurn.call(
          conversation: @workflow_run.conversation,
          content: @workflow_run.turn.selected_input_message.content,
          agent_deployment: @deployment,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {}
        )
        retried_workflow_run = Workflows::CreateForTurn.call(
          turn: retried_turn,
          root_node_key: root_node.node_key,
          root_node_type: root_node.node_type,
          decision_source: root_node.decision_source,
          metadata: root_node.metadata,
          selector_source: "manual_recovery",
          selector: @selector.presence || @workflow_run.turn.recovery_selector
        )

        AuditLog.record!(
          installation: @workflow_run.installation,
          action: "workflow.manual_retried",
          actor: @actor,
          subject: retried_workflow_run,
          metadata: {
            "paused_workflow_run_id" => @workflow_run.id,
            "paused_turn_id" => @workflow_run.turn.id,
            "deployment_id" => @deployment.id,
            "temporary_selector_override" => @selector,
          }.compact
        )

        retried_workflow_run
      end
    end

    private

    def validate_retry_state!
      return if @workflow_run.paused_agent_unavailable?

      raise_invalid!(@workflow_run, :wait_reason_kind, "must require manual recovery before retrying")
    end

    def validate_retry_target!
      raise_invalid!(@workflow_run.turn, :agent_deployment, "must belong to the same installation") unless same_installation?
      raise_invalid!(@workflow_run.turn, :agent_deployment, "must be eligible for scheduling to retry paused work") unless @deployment.eligible_for_scheduling?
      raise_invalid!(@workflow_run.turn, :selected_input_message, "must exist to retry paused work") if @workflow_run.turn.selected_input_message.blank?
    end

    def same_installation?
      @deployment.installation_id == @workflow_run.installation_id
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
