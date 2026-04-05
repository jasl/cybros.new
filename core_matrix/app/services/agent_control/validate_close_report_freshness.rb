module AgentControl
  class ValidateCloseReportFreshness
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, execution_session: nil, payload:, mailbox_item:, resource:, occurred_at: Time.current)
      @deployment = deployment
      @execution_session = execution_session
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

      return unless @mailbox_item.execution_plane?

      resource_environment = ClosableResourceRouting.execution_runtime_for(@resource)
      stale! if resource_environment.blank?
      stale! unless @mailbox_item.target_execution_runtime_id == resource_environment.id

      if @execution_session.present?
        stale! unless @execution_session.execution_runtime_id == resource_environment.id
      else
        stale! unless ExecutionSessions::ResolveActiveSession.call(execution_runtime: resource_environment).present?
      end
    end

    private

    def lease_owner
      return @execution_session if @mailbox_item.execution_plane?

      @deployment
    end

    def stale!
      raise Report::StaleReportError
    end
  end
end
