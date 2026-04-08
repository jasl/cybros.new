module AgentControl
  class Poll
    DEFAULT_LIMIT = 20

    def self.call(...)
      new(...).call
    end

    def initialize(deployment: nil, agent_session: nil, executor_session: nil, limit: DEFAULT_LIMIT, occurred_at: Time.current)
      @deployment = deployment
      @agent_session = agent_session
      @executor_session = executor_session
      @limit = [limit.to_i, 1].max
      @occurred_at = occurred_at
      @resolution_cache = ResolveTargetRuntime::SessionCache.new(
        agent_session: @agent_session,
        executor_session: @executor_session
      )
    end

    def call
      touch_runtime_activity!
      progress_close_requests!

      deliveries = []

      candidate_scope.limit(@limit * 10).each do |mailbox_item|
        break if deliveries.size >= @limit
        resolution = resolution_for(mailbox_item)
        next unless delivery_candidate?(mailbox_item, resolution)

        if mailbox_item.leased? && mailbox_item.leased_to?(lease_owner) && !mailbox_item.lease_stale?(at: @occurred_at)
          deliveries << mailbox_item
          next
        end

        leased_item = LeaseMailboxItem.call(
          mailbox_item: mailbox_item,
          deployment: lease_owner,
          resolved_delivery_endpoint: resolution.delivery_endpoint,
          occurred_at: @occurred_at
        )
        deliveries << leased_item if leased_item.present?
      end

      deliveries
    end

    private

    def touch_runtime_activity!
      return if @executor_session.present?

      TouchDeploymentActivity.call(deployment: @deployment, agent_session: @agent_session, occurred_at: @occurred_at)
    end

    def progress_close_requests!
      close_request_scope.find_each do |mailbox_item|
        ProgressCloseRequest.call(
          mailbox_item: mailbox_item,
          occurred_at: @occurred_at
        )
      end
    end

    def close_request_scope
      scoped_relation = AgentControlMailboxItem.where(
        installation_id: installation_id,
        item_type: "resource_close_request",
        status: ProgressCloseRequest::ACTIVE_STATUSES
      )

      candidate_scope_relation(scoped_relation)
    end

    def candidate_scope
      candidate_scope_relation(
        AgentControlMailboxItem.where(installation_id: installation_id)
      )
        .includes(:agent_task_run)
        .where(status: %w[queued leased])
        .where("available_at <= ?", @occurred_at)
        .order(priority: :asc, available_at: :asc, id: :asc)
    end

    def candidate_scope_relation(relation)
      if execution_poll?
        ResolveTargetRuntime.candidate_scope_for_executor_session(
          executor_session: @executor_session,
          relation: relation
        )
      else
        ResolveTargetRuntime.candidate_scope_for(
          deployment: @deployment,
          relation: relation
        )
      end
    end

    def delivery_candidate?(mailbox_item, resolution)
      return false unless mailbox_item_deliverable?(mailbox_item)
      return true if execution_poll?

      return false if resolution.blank?

      if mailbox_item.leased? && mailbox_item.leased_to?(lease_owner) && !mailbox_item.lease_stale?(at: @occurred_at)
        return true
      end

      resolution.matches?(lease_owner)
    end

    def mailbox_item_deliverable?(mailbox_item)
      return true if execution_poll?

      return true unless mailbox_item.execution_assignment?

      mailbox_item.agent_task_run&.queued?
    end

    def execution_poll?
      @executor_session.present?
    end

    def resolution_for(mailbox_item)
      return execution_resolution if execution_poll?

      ResolveTargetRuntime.call(
        mailbox_item: mailbox_item,
        session_cache: @resolution_cache
      )
    end

    def execution_resolution
      @execution_resolution ||= ResolveTargetRuntime::Result.new(
        control_plane: ResolveTargetRuntime::EXECUTOR_PLANE,
        executor_program: @executor_session.executor_program,
        delivery_endpoint: @executor_session
      )
    end

    def lease_owner
      execution_poll? ? @executor_session : @deployment
    end

    def installation_id
      execution_poll? ? @executor_session.executor_program.installation_id : @deployment.installation_id
    end
  end
end
