module AgentSnapshots
  class RecordHeartbeat
    def self.call(...)
      new(...).call
    end

    def initialize(agent_connection: nil, agent_snapshot: nil, health_status:, health_metadata:, auto_resume_eligible:, unavailability_reason: nil, occurred_at: Time.current)
      @agent_connection = agent_connection
      @agent_snapshot = agent_snapshot || agent_connection&.agent_snapshot
      @health_status = health_status
      @health_metadata = health_metadata
      @auto_resume_eligible = auto_resume_eligible
      @unavailability_reason = unavailability_reason
      @occurred_at = occurred_at
    end

    def call
      session = resolved_agent_connection

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

    def resolved_agent_connection
      session = @agent_connection || @agent_snapshot&.active_agent_connection || @agent_snapshot&.most_recent_agent_connection
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentConnection" if session.blank?
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentConnection" if @agent_snapshot.present? && session.agent_snapshot_id != @agent_snapshot.id

      session
    end

    def resolved_unavailability_reason
      return @unavailability_reason if @unavailability_reason.present?
      return nil if @health_status.to_s == "healthy"

      @agent_connection&.unavailability_reason
    end
  end
end
