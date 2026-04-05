module AgentControl
  class PublishPending
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item: nil, deployment: nil, agent_session: nil, execution_session: nil, resolved_delivery_endpoint: nil, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @deployment = deployment
      @agent_session = agent_session
      @execution_session = execution_session
      @resolved_delivery_endpoint = resolved_delivery_endpoint
      @occurred_at = occurred_at
    end

    def call
      return publish_for_deployment! if @deployment.present?
      return publish_for_execution_session! if @execution_session.present?
      return unless @mailbox_item.present?

      resolution = routing_resolution_for(@mailbox_item)
      target_deployment = connected_target_for(@mailbox_item, resolution)
      return if target_deployment.blank?

      leased_item = LeaseMailboxItem.call(
        mailbox_item: @mailbox_item,
        deployment: target_deployment,
        resolved_delivery_endpoint: resolution.delivery_endpoint,
        occurred_at: @occurred_at
      )
      return if leased_item.blank?

      broadcast(mailbox_item: leased_item, deployment: target_deployment)
      leased_item
    end

    private

    def publish_for_deployment!
      mailbox_items = Poll.call(deployment: @deployment, agent_session: @agent_session, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      serialized_items = SerializeMailboxItems.call(mailbox_items)

      mailbox_items.zip(serialized_items).each do |mailbox_item, serialized_item|
        broadcast(mailbox_item:, deployment: @deployment, serialized_item:)
      end
    end

    def publish_for_execution_session!
      mailbox_items = Poll.call(execution_session: @execution_session, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      serialized_items = SerializeMailboxItems.call(mailbox_items)

      mailbox_items.zip(serialized_items).each do |mailbox_item, serialized_item|
        broadcast(mailbox_item:, deployment: @execution_session, serialized_item:)
      end
    end

    def connected_target_for(mailbox_item, resolution)
      delivery_endpoint = @resolved_delivery_endpoint || resolution.delivery_endpoint
      return if delivery_endpoint.blank? || !delivery_endpoint.realtime_link_connected?

      case delivery_endpoint
      when AgentSession
        delivery_endpoint.agent_program_version
      when ExecutionSession
        delivery_endpoint
      else
        nil
      end
    end

    def routing_resolution_for(mailbox_item)
      ResolveTargetRuntime.call(mailbox_item: mailbox_item)
    end

    def broadcast(mailbox_item:, deployment:, serialized_item: nil)
      ActionCable.server.broadcast(
        StreamName.for_deployment(deployment),
        serialized_item || SerializeMailboxItem.call(mailbox_item)
      )
    end
  end
end
