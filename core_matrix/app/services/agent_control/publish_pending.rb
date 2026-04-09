module AgentControl
  class PublishPending
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item: nil, deployment: nil, agent_session: nil, executor_session: nil, resolved_delivery_endpoint: nil, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @deployment = deployment
      @agent_session = agent_session
      @executor_session = executor_session
      @resolved_delivery_endpoint = resolved_delivery_endpoint
      @occurred_at = occurred_at
    end

    def call
      return publish_for_deployment! if @deployment.present?
      return publish_for_executor_session! if @executor_session.present?
      return unless @mailbox_item.present?

      delivery_endpoint = resolved_delivery_endpoint_for(@mailbox_item)
      target_deployment = connected_target_for(delivery_endpoint)
      return if target_deployment.blank?

      prior_delivery_no = @mailbox_item.delivery_no
      leased_item = LeaseMailboxItem.call(
        mailbox_item: @mailbox_item,
        deployment: target_deployment,
        resolved_delivery_endpoint: delivery_endpoint,
        occurred_at: @occurred_at
      )
      return if leased_item.blank?

      publish_mailbox_lease_event!(
        mailbox_item: leased_item,
        target_deployment: target_deployment,
        delivery_endpoint: delivery_endpoint,
        prior_delivery_no: prior_delivery_no
      )
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

    def publish_for_executor_session!
      mailbox_items = Poll.call(executor_session: @executor_session, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at)
      serialized_items = SerializeMailboxItems.call(mailbox_items)

      mailbox_items.zip(serialized_items).each do |mailbox_item, serialized_item|
        broadcast(mailbox_item:, deployment: @executor_session, serialized_item:)
      end
    end

    def connected_target_for(delivery_endpoint)
      return if delivery_endpoint.blank? || !delivery_endpoint.realtime_link_connected?

      case delivery_endpoint
      when AgentSession
        delivery_endpoint.agent_program_version
      when ExecutorSession
        delivery_endpoint
      else
        nil
      end
    end

    def resolved_delivery_endpoint_for(mailbox_item)
      return @resolved_delivery_endpoint if @resolved_delivery_endpoint.present?

      if mailbox_item.executor_plane?
        return if mailbox_item.target_executor_program.blank?

        return ExecutorSessions::ResolveActiveSession.call(executor_program: mailbox_item.target_executor_program)
      end

      target_agent_program_version = mailbox_item.target_agent_program_version
      return target_agent_program_version.active_agent_session || target_agent_program_version.most_recent_agent_session if target_agent_program_version.present?

      AgentSession.find_by(agent_program: mailbox_item.target_agent_program, lifecycle_state: "active")
    end

    def broadcast(mailbox_item:, deployment:, serialized_item: nil)
      ActionCable.server.broadcast(
        StreamName.for_deployment(deployment),
        serialized_item || SerializeMailboxItem.call(mailbox_item)
      )
    end

    def publish_mailbox_lease_event!(mailbox_item:, target_deployment:, delivery_endpoint:, prior_delivery_no:)
      return unless mailbox_item.delivery_no > prior_delivery_no.to_i

      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        agent_program_public_id: target_deployment.is_a?(AgentProgramVersion) ? target_deployment.agent_program.public_id : nil,
        agent_session_public_id: delivery_endpoint.is_a?(AgentSession) ? delivery_endpoint.public_id : nil,
        executor_session_public_id: delivery_endpoint.is_a?(ExecutorSession) ? delivery_endpoint.public_id : nil
      )
    end
  end
end
