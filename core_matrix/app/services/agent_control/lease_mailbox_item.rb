module AgentControl
  class LeaseMailboxItem
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item:, deployment:, resolved_delivery_endpoint: nil, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @deployment = deployment
      @resolved_delivery_endpoint = resolved_delivery_endpoint
      @occurred_at = occurred_at
    end

    def call
      @mailbox_item.with_lock do
        expire_if_past_deadline!
        return if terminal_status?
        return if @mailbox_item.available_at > @occurred_at

        if @mailbox_item.leased?
          return @mailbox_item if @mailbox_item.leased_to?(@deployment) && !@mailbox_item.lease_stale?(at: @occurred_at)
          return if !@mailbox_item.lease_stale?(at: @occurred_at)
        end

        @mailbox_item.update_columns(
          status: "leased",
          leased_to_agent_session_id: leased_agent_session&.id,
          leased_to_executor_session_id: leased_executor_session&.id,
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

    def leased_agent_session
      return @leased_agent_session if defined?(@leased_agent_session)
      return @leased_agent_session = @resolved_delivery_endpoint if @resolved_delivery_endpoint.is_a?(AgentSession)

      @leased_agent_session =
        case @deployment
        when AgentProgramVersion
          AgentSession.find_by(agent_program_version: @deployment, lifecycle_state: "active")
        else
          nil
        end
    end

    def leased_executor_session
      return @leased_executor_session if defined?(@leased_executor_session)
      return @leased_executor_session = @resolved_delivery_endpoint if @resolved_delivery_endpoint.is_a?(ExecutorSession)

      @leased_executor_session =
        case @deployment
        when ExecutorSession
          @deployment
        when AgentProgramVersion
          ExecutorSession.find_by(executor_program: @mailbox_item.target_executor_program, lifecycle_state: "active") if @mailbox_item.executor_plane?
        else
          nil
        end
    end
  end
end
