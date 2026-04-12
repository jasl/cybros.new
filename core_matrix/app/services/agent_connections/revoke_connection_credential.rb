module AgentConnections
  class RevokeConnectionCredential
    MissingConnection = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, actor: nil, revoked_at: Time.current)
      @agent_definition_version = agent_definition_version
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
          installation: @agent_definition_version.installation,
          action: "agent_connection.credential_revoked",
          actor: @actor,
          subject: agent_connection,
          metadata: audit_metadata(agent_connection)
        )

        @agent_definition_version
      end
    end

    private

    def audit_metadata(agent_connection)
      {
        "agent_id" => @agent_definition_version.agent_id,
        "agent_definition_version_id" => @agent_definition_version.id,
        "health_status" => agent_connection.health_status,
      }
    end

    def resolved_agent_connection!
      @resolved_agent_connection ||= @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection ||
        raise(MissingConnection, "agent definition version must have an active or recent connection to revoke its connection credential")
    end
  end
end
