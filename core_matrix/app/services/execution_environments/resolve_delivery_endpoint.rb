module ExecutionEnvironments
  class ResolveDeliveryEndpoint
    def self.call(...)
      new(...).call
    end

    def initialize(execution_environment:)
      @execution_environment = execution_environment
    end

    def call
      active_deployments.first || pending_deployments.first
    end

    private

    def active_deployments
      @execution_environment
        .agent_deployments
        .where(bootstrap_state: "active")
        .order(last_control_activity_at: :desc, last_heartbeat_at: :desc, created_at: :desc)
    end

    def pending_deployments
      @execution_environment
        .agent_deployments
        .where(bootstrap_state: "pending")
        .order(last_heartbeat_at: :desc, created_at: :desc)
    end
  end
end
