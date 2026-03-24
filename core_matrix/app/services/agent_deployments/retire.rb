module AgentDeployments
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
        @deployment.update!(
          health_status: "retired",
          bootstrap_state: "superseded",
          auto_resume_eligible: false,
          unavailability_reason: "deployment_retired",
          last_health_check_at: @retired_at
        )
        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_deployment.retired",
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
        "agent_installation_id" => @deployment.agent_installation_id,
        "execution_environment_id" => @deployment.execution_environment_id,
        "health_status" => @deployment.health_status,
        "bootstrap_state" => @deployment.bootstrap_state,
      }
    end
  end
end
