module AgentControl
  class PublishPending
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item: nil, deployment: nil, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @deployment = deployment
      @occurred_at = occurred_at
    end

    def call
      return publish_for_deployment! if @deployment.present?
      return unless @mailbox_item.present?

      target_deployment = connected_target_for(@mailbox_item)
      return if target_deployment.blank?

      leased_item = LeaseMailboxItem.call(
        mailbox_item: @mailbox_item,
        deployment: target_deployment,
        occurred_at: @occurred_at
      )
      return if leased_item.blank?

      ActionCable.server.broadcast(
        StreamName.for_deployment(target_deployment),
        SerializeMailboxItem.call(leased_item)
      )
      leased_item
    end

    private

    def publish_for_deployment!
      Poll.call(deployment: @deployment, limit: Poll::DEFAULT_LIMIT, occurred_at: @occurred_at).each do |mailbox_item|
        ActionCable.server.broadcast(
          StreamName.for_deployment(@deployment),
          SerializeMailboxItem.call(mailbox_item)
        )
      end
    end

    def connected_target_for(mailbox_item)
      if mailbox_item.agent_deployment?
        deployment = mailbox_item.target_agent_deployment
        return deployment if deployment&.realtime_link_state == "connected"

        return
      end

      deployments = AgentDeployment
        .where(agent_installation_id: mailbox_item.target_agent_installation_id, bootstrap_state: "active", realtime_link_state: "connected")
        .order(:id)
        .to_a

      deployments.one? ? deployments.first : nil
    end
  end
end
