module AgentDeployments
  class RotateMachineCredential
    Result = Struct.new(:deployment, :machine_credential, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, actor: nil)
      @deployment = deployment
      @actor = actor
    end

    def call
      machine_credential, machine_credential_digest = AgentDeployment.issue_machine_credential

      ApplicationRecord.transaction do
        @deployment.update!(machine_credential_digest: machine_credential_digest)
        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_deployment.machine_credential_rotated",
          actor: @actor,
          subject: @deployment,
          metadata: audit_metadata
        )

        Result.new(deployment: @deployment, machine_credential: machine_credential)
      end
    end

    private

    def audit_metadata
      {
        "agent_installation_id" => @deployment.agent_installation_id,
        "execution_environment_id" => @deployment.execution_environment_id,
      }
    end
  end
end
