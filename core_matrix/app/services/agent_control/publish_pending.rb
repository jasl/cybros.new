module AgentControl
  class PublishPending
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item: nil, agent_snapshot: nil, agent_connection: nil, execution_runtime_connection: nil, resolved_delivery_endpoint: nil, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @agent_snapshot = agent_snapshot
      @agent_connection = agent_connection
      @execution_runtime_connection = execution_runtime_connection
      @resolved_delivery_endpoint = resolved_delivery_endpoint
      @occurred_at = occurred_at
    end

    def call
      return publish_for_agent_snapshot! if @agent_snapshot.present?
      return publish_for_execution_runtime_connection! if @execution_runtime_connection.present?
      return unless @mailbox_item.present?

      delivery_endpoint = resolved_delivery_endpoint_for(@mailbox_item)
      target_agent_snapshot = connected_target_for(delivery_endpoint)
      return if target_agent_snapshot.blank?

      prior_delivery_no = @mailbox_item.delivery_no
      leased_item = LeaseMailboxItem.call(
        mailbox_item: @mailbox_item,
        agent_snapshot: target_agent_snapshot,
        resolved_delivery_endpoint: delivery_endpoint,
        occurred_at: @occurred_at
      )
      return if leased_item.blank?

      publish_mailbox_lease_event!(
        mailbox_item: leased_item,
        target_agent_snapshot: target_agent_snapshot,
        delivery_endpoint: delivery_endpoint,
        prior_delivery_no: prior_delivery_no
      )
      broadcast(mailbox_item: leased_item, delivery_endpoint: target_agent_snapshot)
      leased_item
    end

    private

    def publish_for_agent_snapshot!
      mailbox_items = Poll.call(agent_snapshot: @agent_snapshot, agent_connection: @agent_connection, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      serialized_items = SerializeMailboxItems.call(mailbox_items)

      mailbox_items.zip(serialized_items).each do |mailbox_item, serialized_item|
        broadcast(mailbox_item:, delivery_endpoint: @agent_snapshot, serialized_item:)
      end
    end

    def publish_for_execution_runtime_connection!
      mailbox_items = Poll.call(execution_runtime_connection: @execution_runtime_connection, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      serialized_items = SerializeMailboxItems.call(mailbox_items)

      mailbox_items.zip(serialized_items).each do |mailbox_item, serialized_item|
        broadcast(mailbox_item:, delivery_endpoint: @execution_runtime_connection, serialized_item:)
      end
    end

    def connected_target_for(delivery_endpoint)
      return if delivery_endpoint.blank? || !delivery_endpoint.realtime_link_connected?

      case delivery_endpoint
      when AgentConnection
        delivery_endpoint.agent_snapshot
      when ExecutionRuntimeConnection
        delivery_endpoint
      else
        nil
      end
    end

    def resolved_delivery_endpoint_for(mailbox_item)
      return @resolved_delivery_endpoint if @resolved_delivery_endpoint.present?

      if mailbox_item.execution_runtime_plane?
        return if mailbox_item.target_execution_runtime.blank?

        return ExecutionRuntimeConnections::ResolveActiveConnection.call(execution_runtime: mailbox_item.target_execution_runtime)
      end

      target_agent_snapshot = mailbox_item.target_agent_snapshot
      return target_agent_snapshot.active_agent_connection || target_agent_snapshot.most_recent_agent_connection if target_agent_snapshot.present?

      AgentConnection.find_by(agent: mailbox_item.target_agent, lifecycle_state: "active")
    end

    def broadcast(mailbox_item:, delivery_endpoint:, serialized_item: nil)
      ActionCable.server.broadcast(
        StreamName.for_delivery_endpoint(delivery_endpoint),
        serialized_item || SerializeMailboxItem.call(mailbox_item)
      )
    end

    def publish_mailbox_lease_event!(mailbox_item:, target_agent_snapshot:, delivery_endpoint:, prior_delivery_no:)
      return unless mailbox_item.delivery_no > prior_delivery_no.to_i

      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        agent_public_id: target_agent_snapshot.is_a?(AgentSnapshot) ? target_agent_snapshot.agent.public_id : nil,
        agent_connection_public_id: delivery_endpoint.is_a?(AgentConnection) ? delivery_endpoint.public_id : nil,
        execution_runtime_connection_public_id: delivery_endpoint.is_a?(ExecutionRuntimeConnection) ? delivery_endpoint.public_id : nil
      )
    end
  end
end
