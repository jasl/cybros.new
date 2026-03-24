module AgentDeployments
  class RevokeMachineCredential
    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, actor: nil, revoked_at: Time.current)
      @deployment = deployment
      @actor = actor
      @revoked_at = revoked_at
    end

    def call
      _, machine_credential_digest = AgentDeployment.issue_machine_credential

      ApplicationRecord.transaction do
        @deployment.update!(
          machine_credential_digest: machine_credential_digest,
          health_status: "offline",
          auto_resume_eligible: false,
          unavailability_reason: "machine_credential_revoked",
          last_health_check_at: @revoked_at
        )
        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_deployment.machine_credential_revoked",
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
      }
    end
  end
end
