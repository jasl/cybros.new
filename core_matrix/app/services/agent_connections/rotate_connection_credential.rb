module AgentConnections
  class RotateConnectionCredential
    Result = Struct.new(:agent_definition_version, :agent_connection_credential, keyword_init: true)

    MissingConnection = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, actor: nil)
      @agent_definition_version = agent_definition_version
      @actor = actor
    end

    def call
      agent_connection = resolved_agent_connection!
      agent_connection_credential, agent_connection_credential_digest = AgentConnection.issue_connection_credential

      ApplicationRecord.transaction do
        agent_connection.update!(connection_credential_digest: agent_connection_credential_digest)
        AuditLog.record!(
          installation: @agent_definition_version.installation,
          action: "agent_connection.credential_rotated",
          actor: @actor,
          subject: agent_connection,
          metadata: audit_metadata
        )

        Result.new(
          agent_definition_version: @agent_definition_version,
          agent_connection_credential: agent_connection_credential
        )
      end
    end

    private

    def audit_metadata
      {
        "agent_id" => @agent_definition_version.agent_id,
        "agent_definition_version_id" => @agent_definition_version.id,
      }
    end

    def resolved_agent_connection!
      @agent_definition_version.active_agent_connection || @agent_definition_version.most_recent_agent_connection ||
        raise(MissingConnection, "agent definition version must have an active or recent connection to rotate its connection credential")
    end
  end
end
