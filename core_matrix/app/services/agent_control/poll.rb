module AgentControl
  class Poll
    DEFAULT_LIMIT = 20

    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot: nil, agent_connection: nil, execution_runtime_connection: nil, limit: DEFAULT_LIMIT, occurred_at: Time.current)
      @agent_snapshot = agent_snapshot
      @agent_connection = agent_connection
      @execution_runtime_connection = execution_runtime_connection
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
            agent_snapshot: lease_owner,
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
      return if @execution_runtime_connection.present?

      TouchAgentConnectionActivity.call(
        agent_snapshot: @agent_snapshot,
        agent_connection: @agent_connection,
        occurred_at: @occurred_at
      )
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
          control_plane: "execution_runtime",
          target_execution_runtime_id: @execution_runtime_connection.execution_runtime_id
        )
      else
        relation.where(
          control_plane: "agent"
        ).where(
          <<~SQL.squish,
            target_agent_snapshot_id = :agent_snapshot_id
            OR (
              target_agent_snapshot_id IS NULL
              AND target_agent_id = :agent_id
            )
          SQL
          agent_snapshot_id: @agent_snapshot.id,
          agent_id: @agent_snapshot.agent_id
        )
      end
    end

    def delivery_candidate?(mailbox_item)
      return false unless mailbox_item_deliverable?(mailbox_item)
      return true if execution_poll?

      if mailbox_item.leased? && mailbox_item.leased_to?(lease_owner) && !mailbox_item.lease_stale?(at: @occurred_at)
        return true
      end

      mailbox_item.target_agent_snapshot_id == @agent_snapshot.id ||
        (
          mailbox_item.target_agent_snapshot_id.blank? &&
          mailbox_item.target_agent_id == @agent_snapshot.agent_id
        )
    end

    def mailbox_item_deliverable?(mailbox_item)
      return true if execution_poll?

      return true unless mailbox_item.execution_assignment?

      mailbox_item.agent_task_run&.queued?
    end

    def execution_poll?
      @execution_runtime_connection.present?
    end

    def resolved_delivery_endpoint_for(mailbox_item)
      return @execution_runtime_connection if execution_poll?
      return @agent_connection if @agent_connection&.agent_snapshot_id == mailbox_item.target_agent_snapshot_id

      target_agent_snapshot = mailbox_item.target_agent_snapshot
      return target_agent_snapshot.active_agent_connection || target_agent_snapshot.most_recent_agent_connection if target_agent_snapshot.present?

      @agent_connection || @agent_snapshot&.active_agent_connection || @agent_snapshot&.most_recent_agent_connection
    end

    def lease_owner
      execution_poll? ? @execution_runtime_connection : @agent_snapshot
    end

    def installation_id
      execution_poll? ? @execution_runtime_connection.execution_runtime.installation_id : @agent_snapshot.installation_id
    end

    def poll_event_payload
      payload = {
        "control_plane" => execution_poll? ? "execution_runtime" : "agent",
        "delivery_count" => 0,
        "success" => false,
      }

      if execution_poll?
        payload["execution_runtime_connection_public_id"] = @execution_runtime_connection.public_id
      else
        payload["agent_public_id"] = @agent_snapshot.agent.public_id
        payload["agent_connection_public_id"] = resolved_agent_connection&.public_id
      end

      payload
    end

    def publish_mailbox_lease_event!(mailbox_item)
      AgentControl::PublishMailboxLeaseEvent.call(
        mailbox_item: mailbox_item,
        agent_public_id: execution_poll? ? nil : agent_public_id,
        agent_connection_public_id: execution_poll? ? nil : resolved_agent_connection&.public_id,
        execution_runtime_connection_public_id: execution_poll? ? @execution_runtime_connection.public_id : nil
      )
    end

    def agent_public_id
      return nil if execution_poll?

      @agent_public_id ||= @agent_snapshot.agent.public_id
    end

    def resolved_agent_connection
      return @resolved_agent_connection if defined?(@resolved_agent_connection)

      @resolved_agent_connection = @agent_connection || @agent_snapshot&.active_agent_connection || @agent_snapshot&.most_recent_agent_connection
    end
  end
end
