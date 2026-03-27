module AgentControl
  class HandleCloseReport
    RESOURCE_TYPES = {
      "AgentTaskRun" => AgentTaskRun,
      "ProcessRun" => ProcessRun,
      "SubagentRun" => SubagentRun,
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, method_id:, payload:, occurred_at: Time.current)
      @deployment = deployment
      @method_id = method_id
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      { mailbox_item: mailbox_item }
    end

    def call
      resource = closable_resource

      ValidateCloseReportFreshness.call(
        deployment: @deployment,
        payload: @payload,
        mailbox_item: mailbox_item,
        resource: resource,
        occurred_at: @occurred_at
      )

      case @method_id
      when "resource_close_acknowledged"
        handle_resource_close_acknowledged!(resource)
      when "resource_closed", "resource_close_failed"
        handle_resource_close_terminal!(resource)
      else
        raise ArgumentError, "unsupported close report #{@method_id}"
      end
    end

    private

    def handle_resource_close_acknowledged!(resource)
      resource.update!(close_state: "acknowledged", close_acknowledged_at: @occurred_at)
      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
    end

    def handle_resource_close_terminal!(resource)
      resource.update!(
        close_state: @method_id == "resource_closed" ? "closed" : "failed",
        close_acknowledged_at: resource.close_acknowledged_at || @occurred_at,
        close_outcome_kind: @payload.fetch("close_outcome_kind"),
        close_outcome_payload: @payload.fetch("close_outcome_payload", {})
      )
      terminalize_closed_resource!(resource)
      mailbox_item.update!(status: "completed", completed_at: @occurred_at)
    end

    def terminalize_closed_resource!(resource)
      case resource
      when AgentTaskRun
        resource.update!(
          lifecycle_state: mailbox_item.payload["request_kind"] == "turn_interrupt" ? "interrupted" : "canceled",
          finished_at: resource.finished_at || @occurred_at,
          terminal_payload: resource.terminal_payload.merge(
            "close_outcome_kind" => resource.close_outcome_kind
          )
        )
      when ProcessRun
        resource.update!(
          lifecycle_state: resource.close_outcome_kind == "residual_abandoned" ? "lost" : "stopped",
          ended_at: resource.ended_at || @occurred_at,
          metadata: resource.metadata.merge(
            "stop_reason" => resource.close_reason_kind,
            "close_request_kind" => mailbox_item.payload["request_kind"]
          )
        )
      when SubagentRun
        resource.update!(
          lifecycle_state: resource.close_state == "failed" ? "failed" : "canceled",
          finished_at: resource.finished_at || @occurred_at
        )
      end

      release_resource_lease!(resource)
      reconcile_turn_interrupt!(resource)
      reconcile_close_operation!(resource)
    end

    def release_resource_lease!(resource)
      return unless resource.respond_to?(:execution_lease)
      return unless resource.execution_lease&.active?

      Leases::Release.call(
        execution_lease: resource.execution_lease,
        holder_key: @deployment.public_id,
        reason: "resource_closed",
        released_at: @occurred_at
      )
    rescue ArgumentError
      nil
    end

    def reconcile_turn_interrupt!(resource)
      turn =
        if resource.respond_to?(:turn)
          resource.turn
        elsif resource.respond_to?(:workflow_run)
          resource.workflow_run&.turn
        end
      return if turn.blank?
      return unless turn.cancellation_reason_kind == "turn_interrupted"

      Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: @occurred_at)
    end

    def reconcile_close_operation!(resource)
      conversation = conversation_for_close_reconciliation(resource)
      return if conversation.blank?

      Conversations::ReconcileCloseOperation.call(
        conversation: conversation,
        occurred_at: @occurred_at
      )
    end

    def conversation_for_close_reconciliation(resource)
      return resource.conversation if resource.respond_to?(:conversation)
      return resource.turn&.conversation if resource.respond_to?(:turn)

      resource.workflow_run&.conversation if resource.respond_to?(:workflow_run)
    end

    def mailbox_item
      @mailbox_item ||= AgentControlMailboxItem.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("mailbox_item_id")
      )
    end

    def closable_resource
      resource_type = @payload.fetch("resource_type")
      resource_class = RESOURCE_TYPES.fetch(resource_type)
      resource_class.find_by!(
        installation_id: @deployment.installation_id,
        public_id: @payload.fetch("resource_id")
      )
    end
  end
end
