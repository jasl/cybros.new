module AgentControl
  class HandleHealthReport
    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, agent_connection: nil, payload:, occurred_at: Time.current)
      @agent_definition_version = agent_definition_version
      @agent_connection = agent_connection
      @payload = payload
      @occurred_at = occurred_at
    end

    def receipt_attributes
      {}
    end

    def call
      resolved_agent_connection.update!(
        health_status: @payload.fetch("health_status"),
        health_metadata: @payload.fetch("health_metadata", {}),
        auto_resume_eligible: @payload.fetch("auto_resume_eligible", resolved_agent_connection.auto_resume_eligible),
        unavailability_reason: @payload["unavailability_reason"],
        last_heartbeat_at: @occurred_at,
        last_health_check_at: @occurred_at
      )
    end

    private

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_connection || @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find AgentConnection")
    end
  end
end
