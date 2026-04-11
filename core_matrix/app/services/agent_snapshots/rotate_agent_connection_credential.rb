module AgentSnapshots
  class RotateAgentConnectionCredential
    Result = Struct.new(:agent_snapshot, :agent_connection_credential, keyword_init: true)

    MissingConnection = Class.new(StandardError)

    def self.call(...)
      new(...).call
    end

    def initialize(agent_snapshot:, actor: nil)
      @agent_snapshot = agent_snapshot
      @actor = actor
    end

    def call
      agent_connection = resolved_agent_connection!
      agent_connection_credential, agent_connection_credential_digest = AgentConnection.issue_connection_credential

      ApplicationRecord.transaction do
        agent_connection.update!(connection_credential_digest: agent_connection_credential_digest)
        AuditLog.record!(
          installation: @agent_snapshot.installation,
          action: "agent_snapshot.agent_connection_credential_rotated",
          actor: @actor,
          subject: agent_connection,
          metadata: audit_metadata
        )

        Result.new(agent_snapshot: @agent_snapshot, agent_connection_credential: agent_connection_credential)
      end
    end

    private

    def audit_metadata
      {
        "agent_id" => @agent_snapshot.agent_id,
        "agent_snapshot_id" => @agent_snapshot.id,
      }
    end

    def resolved_agent_connection!
      @agent_snapshot.active_agent_connection || @agent_snapshot.most_recent_agent_connection ||
        raise(MissingConnection, "agent snapshot must have an active or recent connection to rotate its connection credential")
    end
  end
end
