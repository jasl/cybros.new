module AgentProgramVersions
  class RecordHeartbeat
    def self.call(...)
      new(...).call
    end

    def initialize(agent_session: nil, deployment: nil, health_status:, health_metadata:, auto_resume_eligible:, unavailability_reason: nil, occurred_at: Time.current)
      @agent_session = agent_session
      @deployment = deployment || agent_session&.agent_program_version
      @health_status = health_status
      @health_metadata = health_metadata
      @auto_resume_eligible = auto_resume_eligible
      @unavailability_reason = unavailability_reason
      @occurred_at = occurred_at
    end

    def call
      session = resolved_agent_session

      session.update!(
        health_status: @health_status,
        health_metadata: @health_metadata,
        auto_resume_eligible: @auto_resume_eligible,
        unavailability_reason: resolved_unavailability_reason,
        last_heartbeat_at: @occurred_at,
        last_health_check_at: @occurred_at
      )
      session
    end

    private

    def resolved_agent_session
      session = @agent_session || @deployment&.active_agent_session || @deployment&.most_recent_agent_session
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentSession" if session.blank?
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentSession" if @deployment.present? && session.agent_program_version_id != @deployment.id

      session
    end

    def resolved_unavailability_reason
      return @unavailability_reason if @unavailability_reason.present?
      return nil if @health_status.to_s == "healthy"

      @agent_session&.unavailability_reason
    end
  end
end
