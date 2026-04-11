module AgentSnapshots
  class RevokeAgentConnectionCredential
    MissingConnection = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, actor: nil, revoked_at: Time.current)
      @agent_snapshot = agent_snapshot
      @actor = actor
      @revoked_at = revoked_at
    end

    def call
      agent_connection = resolved_agent_connection!
      _, agent_connection_credential_digest = AgentConnection.issue_connection_credential

      ApplicationRecord.transaction do
        agent_connection.update!(
          connection_credential_digest: agent_connection_credential_digest,
          health_status: "offline",
          auto_resume_eligible: false,
          unavailability_reason: "agent_connection_credential_revoked",
          last_health_check_at: @revoked_at
        )
        AuditLog.record!(
          installation: @agent_snapshot.installation,
          action: "agent_snapshot.agent_connection_credential_revoked",
          actor: @actor,
          subject: agent_connection,
          metadata: audit_metadata
        )

        @agent_snapshot
      end
    end

    private

    def audit_metadata
      {
        "agent_id" => @agent_snapshot.agent_id,
        "agent_snapshot_id" => @agent_snapshot.id,
        "health_status" => resolved_agent_connection!.health_status,
      }
    end

    def resolved_agent_connection!
      @resolved_agent_connection ||= @agent_snapshot.active_agent_connection || @agent_snapshot.most_recent_agent_connection ||
        raise(MissingConnection, "agent snapshot must have an active or recent connection to revoke its connection credential")
    end
  end
end
