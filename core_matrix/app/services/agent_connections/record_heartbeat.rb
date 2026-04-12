module AgentConnections
  class RecordHeartbeat
    def self.call(...)
      new(...).call
    end

    def initialize(agent_connection: nil, agent_definition_version: nil, health_status:, health_metadata:, auto_resume_eligible:, unavailability_reason: nil, occurred_at: Time.current)
      @agent_connection = agent_connection
      @agent_definition_version = agent_definition_version || agent_connection&.agent_definition_version
      @health_status = health_status
      @health_metadata = health_metadata
      @auto_resume_eligible = auto_resume_eligible
      @unavailability_reason = unavailability_reason
      @occurred_at = occurred_at
    end

    def call
      agent_connection = resolved_agent_connection!

      agent_connection.update!(
        health_status: @health_status,
        health_metadata: @health_metadata,
        auto_resume_eligible: @auto_resume_eligible,
        unavailability_reason: resolved_unavailability_reason,
        last_heartbeat_at: @occurred_at,
        last_health_check_at: @occurred_at
      )
      agent_connection
    end

    private

    def resolved_agent_connection!
      agent_connection = @agent_connection || @agent_definition_version&.active_agent_connection || @agent_definition_version&.most_recent_agent_connection
      raise ActiveRecord::RecordNotFound, "Couldn't find AgentConnection" if agent_connection.blank?
      if @agent_definition_version.present? && agent_connection.agent_definition_version_id != @agent_definition_version.id
        raise ActiveRecord::RecordNotFound, "Couldn't find AgentConnection"
      end

      agent_connection
    end

    def resolved_unavailability_reason
      return @unavailability_reason if @unavailability_reason.present?
      return nil if @health_status.to_s == "healthy"

      @agent_connection&.unavailability_reason
    end
  end
end
