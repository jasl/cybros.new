module AgentControl
  class ValidateCloseReportFreshness
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, payload:, mailbox_item:, resource:, occurred_at: Time.current)
      @deployment = deployment
      @payload = payload
      @mailbox_item = mailbox_item
      @resource = resource
      @occurred_at = occurred_at
    end

    def call
      stale! unless @mailbox_item.resource_close_request?
      stale! unless @mailbox_item.leased_to?(@deployment)
      stale! if @mailbox_item.leased? && @mailbox_item.lease_stale?(at: @occurred_at)
      stale! unless @mailbox_item.payload["resource_type"] == @resource.class.name
      stale! unless @mailbox_item.payload["resource_id"] == @resource.public_id
      stale! unless @mailbox_item.public_id == @payload["close_request_id"]
      stale! unless @resource.close_requested_at.present?
      stale! if @resource.close_closed? || @resource.close_failed?

      return unless @mailbox_item.environment_plane?

      resource_environment = ClosableResourceRouting.execution_environment_for(@resource)
      stale! if resource_environment.blank?
      stale! unless @mailbox_item.target_execution_environment_id == resource_environment.id
      stale! unless @deployment.execution_environment_id == resource_environment.id
    end

    private

    def stale!
      raise Report::StaleReportError
    end
  end
end
