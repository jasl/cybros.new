module AgentProgramVersions
  class RotateMachineCredential
    Result = Struct.new(:deployment, :machine_credential, keyword_init: true)

    MissingSession = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, actor: nil)
      @deployment = deployment
      @actor = actor
    end

    def call
      session = resolved_agent_session!
      machine_credential, machine_credential_digest = AgentSession.issue_session_credential

      ApplicationRecord.transaction do
        session.update!(session_credential_digest: machine_credential_digest)
        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_program_version.machine_credential_rotated",
          actor: @actor,
          subject: session,
          metadata: audit_metadata
        )

        Result.new(deployment: @deployment, machine_credential: machine_credential)
      end
    end

    private

    def audit_metadata
      {
        "agent_program_id" => @deployment.agent_program_id,
        "agent_program_version_id" => @deployment.id,
      }
    end

    def resolved_agent_session!
      @deployment.active_agent_session || @deployment.most_recent_agent_session ||
        raise(MissingSession, "agent program version must have a session to rotate its machine credential")
    end
  end
end
