module AgentDeployments
  class RecordHeartbeat
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, health_status:, health_metadata:, auto_resume_eligible:, unavailability_reason: nil, checked_at: Time.current)
      @deployment = deployment
      @health_status = health_status
      @health_metadata = health_metadata
      @auto_resume_eligible = auto_resume_eligible
      @unavailability_reason = unavailability_reason
      @checked_at = checked_at
    end

    def call
      @deployment.update!(
        health_status: @health_status,
        health_metadata: @health_metadata,
        last_heartbeat_at: @checked_at,
        last_health_check_at: @checked_at,
        auto_resume_eligible: @auto_resume_eligible,
        unavailability_reason: @health_status == "healthy" ? nil : @unavailability_reason,
        bootstrap_state: next_bootstrap_state
      )

      @deployment
    end

    private

    def next_bootstrap_state
      return "active" if @deployment.pending? && @health_status == "healthy"

      @deployment.bootstrap_state
    end
  end
end
