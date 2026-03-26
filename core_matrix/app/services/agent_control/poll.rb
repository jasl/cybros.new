module AgentControl
  class Poll
    DEFAULT_LIMIT = 20

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, limit: DEFAULT_LIMIT, occurred_at: Time.current)
      @deployment = deployment
      @limit = [limit.to_i, 1].max
      @occurred_at = occurred_at
    end

    def call
      TouchDeploymentActivity.call(deployment: @deployment, occurred_at: @occurred_at)

      deliveries = []

      candidate_scope.limit(@limit * 5).each do |mailbox_item|
        break if deliveries.size >= @limit

        if mailbox_item.leased? && mailbox_item.leased_to?(@deployment) && !mailbox_item.lease_stale?(at: @occurred_at)
          deliveries << mailbox_item
          next
        end

        leased_item = LeaseMailboxItem.call(
          mailbox_item: mailbox_item,
          deployment: @deployment,
          occurred_at: @occurred_at
        )
        deliveries << leased_item if leased_item.present?
      end

      deliveries
    end

    private

    def candidate_scope
      AgentControlMailboxItem
        .where(installation_id: @deployment.installation_id)
        .where(
          "target_agent_deployment_id = :deployment_id OR (target_agent_deployment_id IS NULL AND target_agent_installation_id = :agent_installation_id)",
          deployment_id: @deployment.id,
          agent_installation_id: @deployment.agent_installation_id
        )
        .where(status: %w[queued leased])
        .where("available_at <= ?", @occurred_at)
        .order(priority: :asc, available_at: :asc, id: :asc)
      end
  end
end
