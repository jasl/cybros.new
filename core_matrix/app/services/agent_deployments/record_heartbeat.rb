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
      ApplicationRecord.transaction do
        lock_related_deployments!
        supersede_previous_active_deployments! if promoting_pending_deployment?

        @deployment.reload
        @deployment.update!(
          health_status: @health_status,
          health_metadata: @health_metadata,
          last_heartbeat_at: @checked_at,
          last_health_check_at: @checked_at,
          auto_resume_eligible: @auto_resume_eligible,
          unavailability_reason: @health_status == "healthy" ? nil : @unavailability_reason,
          bootstrap_state: next_bootstrap_state
        )
      end

      @deployment
    end

    private

    def lock_related_deployments!
      AgentDeployment.where(agent_installation_id: @deployment.agent_installation_id).lock.load
    end

    def supersede_previous_active_deployments!
      AgentDeployment
        .where(agent_installation_id: @deployment.agent_installation_id, bootstrap_state: "active")
        .where.not(id: @deployment.id)
        .update_all(bootstrap_state: "superseded", updated_at: @checked_at)
    end

    def promoting_pending_deployment?
      @deployment.pending? && @health_status == "healthy"
    end

    def next_bootstrap_state
      return "active" if promoting_pending_deployment?

      @deployment.bootstrap_state
    end
  end
end
