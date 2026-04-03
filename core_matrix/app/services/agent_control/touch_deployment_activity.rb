module AgentControl
  class TouchDeploymentActivity
    def self.call(...)
      new(...).call
    end

    def initialize(deployment: nil, agent_session: nil, occurred_at: Time.current)
      @deployment = deployment
      @agent_session = agent_session
      @occurred_at = occurred_at
    end

    def call
      resolved_agent_session.update!(
        control_activity_state: "active",
        last_control_activity_at: @occurred_at
      )
      resolved_agent_session
    end

    private

    def resolved_agent_session
      @resolved_agent_session ||= @agent_session || @deployment&.active_agent_session || @deployment&.most_recent_agent_session ||
        raise(ActiveRecord::RecordNotFound, "Couldn't find AgentSession")
    end
  end
end
