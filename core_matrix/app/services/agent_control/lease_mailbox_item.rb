module AgentControl
  class LeaseMailboxItem
    def self.call(...)
      new(...).call
    end

    def initialize(mailbox_item:, deployment:, occurred_at: Time.current)
      @mailbox_item = mailbox_item
      @deployment = deployment
      @occurred_at = occurred_at
    end

    def call
      @mailbox_item.with_lock do
        @mailbox_item.reload
        expire_if_past_deadline!
        return if terminal_status?
        return if @mailbox_item.available_at > @occurred_at

        if @mailbox_item.leased?
          return @mailbox_item if @mailbox_item.leased_to?(@deployment) && !@mailbox_item.lease_stale?(at: @occurred_at)
          return if !@mailbox_item.lease_stale?(at: @occurred_at)
        end

        @mailbox_item.update!(
          status: "leased",
          leased_to_agent_session: leased_agent_session,
          leased_to_execution_session: leased_execution_session,
          leased_at: @occurred_at,
          lease_expires_at: @occurred_at + @mailbox_item.lease_timeout_seconds.seconds,
          delivery_no: @mailbox_item.delivery_no + 1
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

      @mailbox_item.update!(status: "expired", failed_at: @occurred_at)
    end

    def leased_agent_session
      return @leased_agent_session if defined?(@leased_agent_session)

      @leased_agent_session =
        case @deployment
        when AgentProgramVersion
          AgentSession.find_by(agent_program_version: @deployment, lifecycle_state: "active")
        else
          nil
        end
    end

    def leased_execution_session
      return @leased_execution_session if defined?(@leased_execution_session)

      @leased_execution_session =
        case @deployment
        when ExecutionSession
          @deployment
        when AgentProgramVersion
          ExecutionSession.find_by(execution_runtime: @mailbox_item.target_execution_runtime, lifecycle_state: "active") if @mailbox_item.execution_plane?
        else
          nil
        end
    end
  end
end
