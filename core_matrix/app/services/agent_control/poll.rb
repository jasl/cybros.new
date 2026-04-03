module AgentControl
  class Poll
    DEFAULT_LIMIT = 20

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, agent_session: nil, limit: DEFAULT_LIMIT, occurred_at: Time.current)
      @deployment = deployment
      @agent_session = agent_session
      @limit = [limit.to_i, 1].max
      @occurred_at = occurred_at
    end

    def call
      TouchDeploymentActivity.call(deployment: @deployment, agent_session: @agent_session, occurred_at: @occurred_at)
      progress_close_requests!

      deliveries = []

      candidate_scope.limit(@limit * 10).each do |mailbox_item|
        break if deliveries.size >= @limit
        next unless delivery_candidate?(mailbox_item)

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

    def progress_close_requests!
      close_request_scope.find_each do |mailbox_item|
        ProgressCloseRequest.call(
          mailbox_item: mailbox_item,
          occurred_at: @occurred_at
        )
      end
    end

    def close_request_scope
      ResolveTargetRuntime
        .candidate_scope_for(
          deployment: @deployment,
          relation: AgentControlMailboxItem.where(
            installation_id: @deployment.installation_id,
            item_type: "resource_close_request",
            status: ProgressCloseRequest::ACTIVE_STATUSES
          )
        )
    end

    def candidate_scope
      ResolveTargetRuntime
        .candidate_scope_for(
          deployment: @deployment,
          relation: AgentControlMailboxItem.where(installation_id: @deployment.installation_id)
        )
        .where(status: %w[queued leased])
        .where("available_at <= ?", @occurred_at)
        .order(priority: :asc, available_at: :asc, id: :asc)
    end

    def delivery_candidate?(mailbox_item)
      return false unless mailbox_item_deliverable?(mailbox_item)

      resolution = ResolveTargetRuntime.call(mailbox_item: mailbox_item)

      if mailbox_item.leased? && mailbox_item.leased_to?(@deployment) && !mailbox_item.lease_stale?(at: @occurred_at)
        return true
      end

      resolution.matches?(@deployment)
    end

    def mailbox_item_deliverable?(mailbox_item)
      return true unless mailbox_item.execution_assignment?

      mailbox_item.agent_task_run&.queued?
    end
  end
end
