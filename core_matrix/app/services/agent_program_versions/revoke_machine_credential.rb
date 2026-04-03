module AgentProgramVersions
  class RevokeMachineCredential
    MissingSession = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(deployment:, actor: nil, revoked_at: Time.current)
      @deployment = deployment
      @actor = actor
      @revoked_at = revoked_at
    end

    def call
      session = resolved_agent_session!
      _, machine_credential_digest = AgentSession.issue_session_credential

      ApplicationRecord.transaction do
        session.update!(
          session_credential_digest: machine_credential_digest,
          health_status: "offline",
          auto_resume_eligible: false,
          unavailability_reason: "machine_credential_revoked",
          last_health_check_at: @revoked_at
        )
        AuditLog.record!(
          installation: @deployment.installation,
          action: "agent_program_version.machine_credential_revoked",
          actor: @actor,
          subject: session,
          metadata: audit_metadata
        )

        @deployment
      end
    end

    private

    def audit_metadata
      {
        "agent_program_id" => @deployment.agent_program_id,
        "agent_program_version_id" => @deployment.id,
        "health_status" => resolved_agent_session!.health_status,
      }
    end

    def resolved_agent_session!
      @resolved_agent_session ||= @deployment.active_agent_session || @deployment.most_recent_agent_session ||
        raise(MissingSession, "agent program version must have a session to revoke its machine credential")
    end
  end
end
