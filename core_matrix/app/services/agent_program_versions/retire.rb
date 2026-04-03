module AgentProgramVersions
  class Retire
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, actor: nil, retired_at: Time.current)
      @deployment = deployment
      @actor = actor
      @retired_at = retired_at
    end

    def call
      ApplicationRecord.transaction do
        resolved_agent_session&.update!(
          lifecycle_state: "closed",
          health_status: "retired",
          auto_resume_eligible: false,
          unavailability_reason: "deployment_retired",
          control_activity_state: "idle",
          last_health_check_at: @retired_at
        )
        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_program_version.retired",
          actor: @actor,
          subject: @deployment,
          metadata: audit_metadata
        )

        @deployment
      end
    end

    private

    def audit_metadata
      {
        "agent_program_id" => @deployment.agent_program_id,
        "execution_runtime_id" => @deployment.agent_program.default_execution_runtime_id,
        "health_status" => @deployment.health_status,
        "bootstrap_state" => @deployment.bootstrap_state,
      }
    end

    def resolved_agent_session
      @resolved_agent_session ||= @deployment.active_agent_session || @deployment.most_recent_agent_session
    end
  end
end
