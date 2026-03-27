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

      ApplicationRecord.transaction do
        Workflows::WithMutableWorkflowContext.call(
          workflow_run: @workflow_run,
          retained_message: "must be retained before manual retry",
          active_message: "must be active before manual retry",
          closing_message: "must not retry paused work while close is in progress"
        ) do |conversation, workflow_run, turn|
          validate_retry_state!(workflow_run)
          validate_retry_target!(workflow_run, turn)
          root_node = workflow_run.workflow_nodes.order(:ordinal).first
          raise_invalid!(workflow_run, :workflow_nodes, "must include a root node to retry") if root_node.blank?

          workflow_run.update!(lifecycle_state: "canceled")
          turn.update!(lifecycle_state: "canceled")
          Conversations::SwitchAgentDeployment.call(
            conversation: conversation,
            agent_deployment: @deployment
          )

          retried_turn = Turns::StartUserTurn.call(
            conversation: conversation,
            content: turn.selected_input_message.content,
            agent_deployment: conversation.agent_deployment,
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
            selector: @selector.presence || turn.recovery_selector
          )

          AuditLog.record!(
            installation: workflow_run.installation,
            action: "workflow.manual_retried",
            actor: @actor,
            subject: retried_workflow_run,
            metadata: {
              "paused_workflow_run_id" => workflow_run.id,
              "paused_turn_id" => turn.id,
              "deployment_id" => @deployment.id,
              "temporary_selector_override" => @selector,
            }.compact
          )

          retried_workflow_run
        end
      end
    end

    private

    def validate_retry_state!(workflow_run = @workflow_run)
      return if workflow_run.paused_agent_unavailable?

      raise_invalid!(workflow_run, :wait_reason_kind, "must require manual recovery before retrying")
    end

    def validate_retry_target!(workflow_run, turn)
      raise_invalid!(turn, :agent_deployment, "must be eligible for scheduling to retry paused work") unless @deployment.eligible_for_scheduling?
      raise_invalid!(turn, :selected_input_message, "must exist to retry paused work") if turn.selected_input_message.blank?
      Conversations::ValidateAgentDeploymentTarget.call(
        conversation: workflow_run.conversation,
        agent_deployment: @deployment,
        record: turn
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
