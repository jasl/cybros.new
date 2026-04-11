module AgentControl
  class LeaseMailboxItem
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item:, agent_snapshot:, resolved_delivery_endpoint: nil, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @agent_snapshot = agent_snapshot
      @resolved_delivery_endpoint = resolved_delivery_endpoint
      @occurred_at = occurred_at
    end

    def call
      @mailbox_item.with_lock do
        expire_if_past_deadline!
        return if terminal_status?
        return if @mailbox_item.available_at > @occurred_at

        if @mailbox_item.leased?
          return @mailbox_item if @mailbox_item.leased_to?(@agent_snapshot) && !@mailbox_item.lease_stale?(at: @occurred_at)
          return if !@mailbox_item.lease_stale?(at: @occurred_at)
        end

        @mailbox_item.update_columns(
          status: "leased",
          leased_to_agent_connection_id: leased_agent_connection&.id,
          leased_to_execution_runtime_connection_id: leased_execution_runtime_connection&.id,
          leased_at: @occurred_at,
          lease_expires_at: @occurred_at + @mailbox_item.lease_timeout_seconds.seconds,
          delivery_no: @mailbox_item.delivery_no + 1,
          updated_at: @occurred_at
        )
        @mailbox_item
      end
    end

    private

    def terminal_status?
      @mailbox_item.completed? || @mailbox_item.failed? || @mailbox_item.expired? || @mailbox_item.canceled?
    end

    def expire_if_past_deadline!
      return unless @mailbox_item.dispatch_deadline_at < @occurred_at

      @mailbox_item.update_columns(
        status: "expired",
        failed_at: @occurred_at,
        updated_at: @occurred_at
      )
    end

    def leased_agent_connection
      return @leased_agent_connection if defined?(@leased_agent_connection)
      return @leased_agent_connection = @resolved_delivery_endpoint if @resolved_delivery_endpoint.is_a?(AgentConnection)

      @leased_agent_connection =
        case @agent_snapshot
        when AgentSnapshot
          AgentConnection.find_by(agent_snapshot: @agent_snapshot, lifecycle_state: "active")
        else
          nil
        end
    end

    def leased_execution_runtime_connection
      return @leased_execution_runtime_connection if defined?(@leased_execution_runtime_connection)
      return @leased_execution_runtime_connection = @resolved_delivery_endpoint if @resolved_delivery_endpoint.is_a?(ExecutionRuntimeConnection)

      @leased_execution_runtime_connection =
        case @agent_snapshot
        when ExecutionRuntimeConnection
          @agent_snapshot
        when AgentSnapshot
          ExecutionRuntimeConnection.find_by(execution_runtime: @mailbox_item.target_execution_runtime, lifecycle_state: "active") if @mailbox_item.execution_runtime_plane?
        else
          nil
        end
    end
  end
end
