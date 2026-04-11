module AgentControl
  class PublishMailboxLeaseEvent
    EVENT_NAME = "perf.agent_control.mailbox_item_leased".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(
      mailbox_item:,
      agent_public_id: nil,
      agent_connection_public_id: nil,
      execution_runtime_connection_public_id: nil,
      notifier: ActiveSupport::Notifications
    )
      @mailbox_item = mailbox_item
      @agent_public_id = agent_public_id
      @agent_connection_public_id = agent_connection_public_id
      @execution_runtime_connection_public_id = execution_runtime_connection_public_id
      @notifier = notifier
    end

    def call
      @notifier.instrument(EVENT_NAME, payload)
    end

    private

    def payload
      {
        "mailbox_item_public_id" => @mailbox_item.public_id,
        "item_type" => @mailbox_item.item_type,
        "control_plane" => @mailbox_item.control_plane,
        "success" => true,
      }.tap do |payload|
        if @mailbox_item.execution_runtime_plane?
          payload["execution_runtime_connection_public_id"] = @execution_runtime_connection_public_id
        else
          payload["agent_public_id"] = @agent_public_id
          payload["agent_connection_public_id"] = @agent_connection_public_id
        end

        if @mailbox_item.available_at.present? && @mailbox_item.leased_at.present?
          payload["lease_latency_ms"] = ((@mailbox_item.leased_at - @mailbox_item.available_at) * 1000.0).round(3)
        end
      end
    end
  end
end
