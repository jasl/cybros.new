module AgentControl
  class ProgressCloseRequest
    ACTIVE_STATUSES = %w[queued leased acked].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item:, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @occurred_at = occurred_at
    end

    def call
      return @mailbox_item unless @mailbox_item.resource_close_request?
      return @mailbox_item unless ACTIVE_STATUSES.include?(@mailbox_item.status)

      resource = closable_resource
      return @mailbox_item if resource.blank?
      return @mailbox_item if resource.close_closed? || resource.close_failed?

      if force_deadline_reached?(resource)
        return ApplyCloseOutcome.call(
          resource: resource,
          mailbox_item: @mailbox_item,
          close_state: "failed",
          close_outcome_kind: "timed_out_forced",
          close_outcome_payload: {
            "source" => "kernel_timeout",
            "reason" => "force_deadline_elapsed",
          },
          occurred_at: @occurred_at
        )
      end

      return escalate_to_forced! if grace_deadline_reached?(resource) && @mailbox_item.payload["strictness"] != "forced"

      @mailbox_item
    end

    private

    def escalate_to_forced!
      @mailbox_item.update!(
        status: "queued",
        available_at: @occurred_at,
        leased_to_agent_deployment: nil,
        leased_at: nil,
        lease_expires_at: nil,
        acked_at: nil,
        completed_at: nil,
        payload: @mailbox_item.payload.merge("strictness" => "forced")
      )
      @mailbox_item
    end

    def closable_resource
      resource_class = HandleCloseReport::RESOURCE_TYPES.fetch(@mailbox_item.payload.fetch("resource_type"))
      resource_class.find_by(
        installation_id: @mailbox_item.installation_id,
        public_id: @mailbox_item.payload.fetch("resource_id")
      )
    end

    def grace_deadline_reached?(resource)
      resource.close_grace_deadline_at.present? && resource.close_grace_deadline_at <= @occurred_at
    end

    def force_deadline_reached?(resource)
      resource.close_force_deadline_at.present? && resource.close_force_deadline_at <= @occurred_at
    end
  end
end
