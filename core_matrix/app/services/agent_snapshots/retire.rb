module AgentSnapshots
  class Retire
    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, actor: nil, retired_at: Time.current)
      @agent_snapshot = agent_snapshot
      @actor = actor
      @retired_at = retired_at
    end

    def call
      ApplicationRecord.transaction do
        resolved_agent_connection&.update!(
          lifecycle_state: "closed",
          health_status: "retired",
          auto_resume_eligible: false,
          unavailability_reason: "agent_snapshot_retired",
          control_activity_state: "idle",
          last_health_check_at: @retired_at
        )
        AuditLog.record!(
          installation: @agent_snapshot.installation,
          action: "agent_snapshot.retired",
          actor: @actor,
          subject: @agent_snapshot,
          metadata: audit_metadata
        )

        @agent_snapshot
      end
    end

    private

    def audit_metadata
      {
        "agent_id" => @agent_snapshot.agent_id,
        "execution_runtime_id" => @agent_snapshot.agent.default_execution_runtime_id,
        "health_status" => @agent_snapshot.health_status,
        "bootstrap_state" => @agent_snapshot.bootstrap_state,
      }
    end

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_snapshot.active_agent_connection || @agent_snapshot.most_recent_agent_connection
    end
  end
end
