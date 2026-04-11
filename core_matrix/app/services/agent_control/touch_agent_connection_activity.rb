module AgentControl
  class TouchAgentConnectionActivity
    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot: nil, agent_connection: nil, occurred_at: Time.current)
      @agent_snapshot = agent_snapshot
      @agent_connection = agent_connection
      @occurred_at = occurred_at
    end

    def call
      resolved_agent_connection.update_columns(
        control_activity_state: "active",
        last_control_activity_at: @occurred_at,
        updated_at: @occurred_at
      )
      resolved_agent_connection
    end

    private

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_connection || @agent_snapshot&.active_agent_connection || @agent_snapshot&.most_recent_agent_connection ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find AgentConnection")
    end
  end
end
