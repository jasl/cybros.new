module AgentControl
  class ValidateCloseReportFreshness
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, executor_session: nil, payload:, mailbox_item:, resource:, occurred_at: Time.current)
      @deployment = deployment
      @executor_session = executor_session
      @payload = payload
      @mailbox_item = mailbox_item
      @resource = resource
      @occurred_at = occurred_at
    end

    def call
      stale! unless @mailbox_item.resource_close_request?
      stale! unless @mailbox_item.leased_to?(lease_owner)
      stale! if @mailbox_item.leased? && @mailbox_item.lease_stale?(at: @occurred_at)
      stale! unless @mailbox_item.payload["resource_type"] == @resource.class.name
      stale! unless @mailbox_item.payload["resource_id"] == @resource.public_id
      stale! unless @mailbox_item.public_id == @payload["close_request_id"]
      stale! unless @resource.close_requested_at.present?
      stale! if @resource.close_closed? || @resource.close_failed?

      return unless @mailbox_item.executor_plane?

      resource_environment = ClosableResourceRouting.executor_program_for(@resource)
      stale! if resource_environment.blank?
      stale! unless @mailbox_item.target_executor_program_id == resource_environment.id

      if @executor_session.present?
        stale! unless @executor_session.executor_program_id == resource_environment.id
      else
        stale! unless ExecutorSessions::ResolveActiveSession.call(executor_program: resource_environment).present?
      end
    end

    private

    def lease_owner
      return @executor_session if @mailbox_item.executor_plane?

      @deployment
    end

    def stale!
      raise Report::StaleReportError
    end
  end
end
