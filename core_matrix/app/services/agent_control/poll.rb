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
    end

    def call
      payload = poll_event_payload

      ActiveSupport::Notifications.instrument("perf.agent_control.poll", payload) do
        touch_runtime_activity!
        progress_close_requests!

        deliveries = []

        candidate_scope.limit(@limit * 10).each do |mailbox_item|
          break if deliveries.size >= @limit
          next unless delivery_candidate?(mailbox_item)

          if mailbox_item.leased? && mailbox_item.leased_to?(lease_owner) && !mailbox_item.lease_stale?(at: @occurred_at)
            deliveries << mailbox_item
            next
          end

          leased_item = LeaseMailboxItem.call(
            mailbox_item: mailbox_item,
            deployment: lease_owner,
            resolved_delivery_endpoint: resolved_delivery_endpoint_for(mailbox_item),
            occurred_at: @occurred_at
          )
          next unless leased_item.present?

          publish_mailbox_lease_event!(leased_item)
          deliveries << leased_item
        end

        payload["delivery_count"] = deliveries.size
        payload["success"] = true
        deliveries
      end
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
        relation.where(
          control_plane: "executor",
          target_executor_program_id: @executor_session.executor_program_id
        )
      else
        relation.where(
          control_plane: "program"
        ).where(
          <<~SQL.squish,
            target_agent_program_version_id = :deployment_id
            OR (
              target_agent_program_version_id IS NULL
              AND target_agent_program_id = :agent_program_id
            )
          SQL
          deployment_id: @deployment.id,
          agent_program_id: @deployment.agent_program_id
        )
      end
    end

    def delivery_candidate?(mailbox_item)
      return false unless mailbox_item_deliverable?(mailbox_item)
      return true if execution_poll?

      if mailbox_item.leased? && mailbox_item.leased_to?(lease_owner) && !mailbox_item.lease_stale?(at: @occurred_at)
        return true
      end

      mailbox_item.target_agent_program_version_id == @deployment.id ||
        (
          mailbox_item.target_agent_program_version_id.blank? &&
          mailbox_item.target_agent_program_id == @deployment.agent_program_id
        )
    end

    def mailbox_item_deliverable?(mailbox_item)
      return true if execution_poll?

      return true unless mailbox_item.execution_assignment?

      mailbox_item.agent_task_run&.queued?
    end

    def execution_poll?
      @executor_session.present?
    end

    def resolved_delivery_endpoint_for(mailbox_item)
      return @executor_session if execution_poll?
      return @agent_session if @agent_session&.agent_program_version_id == mailbox_item.target_agent_program_version_id

      target_agent_program_version = mailbox_item.target_agent_program_version
      return target_agent_program_version.active_agent_session || target_agent_program_version.most_recent_agent_session if target_agent_program_version.present?

      @agent_session || @deployment&.active_agent_session || @deployment&.most_recent_agent_session
    end

    def lease_owner
      execution_poll? ? @executor_session : @deployment
    end

    def installation_id
      execution_poll? ? @executor_session.executor_program.installation_id : @deployment.installation_id
    end

    def poll_event_payload
      payload = {
        "control_plane" => execution_poll? ? "executor" : "program",
        "delivery_count" => 0,
        "success" => false,
      }

      if execution_poll?
        payload["executor_session_public_id"] = @executor_session.public_id
      else
        payload["agent_program_public_id"] = @deployment.agent_program.public_id
        payload["agent_session_public_id"] = resolved_agent_session&.public_id
      end

      payload
    end

    def publish_mailbox_lease_event!(mailbox_item)
      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        agent_program_public_id: execution_poll? ? nil : deployment_agent_program_public_id,
        agent_session_public_id: execution_poll? ? nil : resolved_agent_session&.public_id,
        executor_session_public_id: execution_poll? ? @executor_session.public_id : nil
      )
    end

    def deployment_agent_program_public_id
      return nil if execution_poll?

      @deployment_agent_program_public_id ||= @deployment.agent_program.public_id
    end

    def resolved_agent_session
      return @resolved_agent_session if defined?(@resolved_agent_session)

      @resolved_agent_session = @agent_session || @deployment&.active_agent_session || @deployment&.most_recent_agent_session
    end
  end
end
