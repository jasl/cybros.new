module AgentDefinitionVersions
  class Retire
    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, actor: nil, retired_at: Time.current)
      @agent_definition_version = agent_definition_version
      @actor = actor
      @retired_at = retired_at
    end

    def call
      ApplicationRecord.transaction do
        resolved_agent_connection&.update!(
          lifecycle_state: "closed",
          health_status: "retired",
          auto_resume_eligible: false,
          unavailability_reason: "agent_definition_version_retired",
          control_activity_state: "idle",
          last_health_check_at: @retired_at
        )
        AuditLog.record!(
          installation: @agent_definition_version.installation,
          action: "agent_definition_version.retired",
          actor: @actor,
          subject: @agent_definition_version,
          metadata: audit_metadata
        )

        @agent_definition_version
      end
    end

    private

    def audit_metadata
      {
        "agent_id" => @agent_definition_version.agent_id,
        "execution_runtime_id" => @agent_definition_version.agent.default_execution_runtime_id,
        "health_status" => @agent_definition_version.health_status,
        "bootstrap_state" => @agent_definition_version.bootstrap_state,
      }
    end

    def resolved_agent_connection
      @resolved_agent_connection ||= @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection
    end
  end
end
