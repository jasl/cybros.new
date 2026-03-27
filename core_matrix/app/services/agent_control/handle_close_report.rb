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
      when "resource_closed"
        handle_resource_closed!(resource)
      when "resource_close_failed"
        handle_resource_close_failed!(resource)
      else
        raise ArgumentError, "unsupported close report #{@method_id}"
      end
    end

    private

    def handle_resource_close_acknowledged!(resource)
      resource.update!(close_state: "acknowledged", close_acknowledged_at: @occurred_at)
      mailbox_item.update!(status: "acked", acked_at: @occurred_at)
    end

    def handle_resource_closed!(resource)
      ApplyCloseOutcome.call(
        resource: resource,
        mailbox_item: mailbox_item,
        close_state: "closed",
        close_outcome_kind: @payload.fetch("close_outcome_kind"),
        close_outcome_payload: @payload.fetch("close_outcome_payload", {}),
        occurred_at: @occurred_at
      )
    end

    def handle_resource_close_failed!(resource)
      ApplyCloseOutcome.call(
        resource: resource,
        mailbox_item: mailbox_item,
        close_state: "failed",
        close_outcome_kind: @payload.fetch("close_outcome_kind"),
        close_outcome_payload: @payload.fetch("close_outcome_payload", {}),
        occurred_at: @occurred_at
      )
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
