module AgentSnapshots
  class Register
    InvalidEnrollment = Class.new(StandardError)
    ExpiredEnrollment = Class.new(StandardError)

    Result = Struct.new(
      :enrollment,
      :execution_runtime,
      :agent_snapshot,
      :agent_connection,
      :agent_connection_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      enrollment_token:,
      fingerprint:,
      endpoint_metadata:,
      protocol_version:,
      sdk_version:,
      protocol_methods:,
      tool_catalog:,
      profile_catalog:,
      config_schema_snapshot:,
      conversation_override_schema_snapshot:,
      default_config_snapshot:
    )
      @enrollment_token = enrollment_token
      @fingerprint = fingerprint
      @endpoint_metadata = endpoint_metadata
      @protocol_version = protocol_version
      @sdk_version = sdk_version
      @protocol_methods = protocol_methods
      @tool_catalog = tool_catalog
      @profile_catalog = profile_catalog
      @config_schema_snapshot = config_schema_snapshot
      @conversation_override_schema_snapshot = conversation_override_schema_snapshot
      @default_config_snapshot = default_config_snapshot
    end

    def call
      enrollment = AgentEnrollment.find_by_plaintext_token(@enrollment_token)
      raise InvalidEnrollment, "enrollment token is invalid" if enrollment.blank?
      raise ExpiredEnrollment, "enrollment token has expired" if enrollment.expired?

      ApplicationRecord.transaction do
        agent_snapshot = find_or_create_agent_snapshot!(agent: enrollment.agent)
        execution_runtime = enrollment.agent.default_execution_runtime

        AgentConnection.where(agent: enrollment.agent, lifecycle_state: "active").update_all(
          lifecycle_state: "stale",
          updated_at: Time.current
        )

        agent_connection_credential, connection_credential_digest = AgentConnection.issue_connection_credential
        _connection_token, connection_token_digest = AgentConnection.issue_connection_token
        agent_connection = AgentConnection.create!(
          installation: enrollment.installation,
          agent: enrollment.agent,
          agent_snapshot: agent_snapshot,
          connection_credential_digest: connection_credential_digest,
          connection_token_digest: connection_token_digest,
          endpoint_metadata: @endpoint_metadata,
          lifecycle_state: "active",
          health_status: "pending",
          health_metadata: {},
          auto_resume_eligible: false,
          last_heartbeat_at: Time.current
        )

        record_audit!(enrollment:, agent_snapshot:, agent_connection:, execution_runtime:)

        Result.new(
          enrollment: enrollment,
          execution_runtime: execution_runtime,
          agent_snapshot: agent_snapshot,
          agent_connection: agent_connection,
          agent_connection_credential: agent_connection_credential
        )
      end
    end

    private

    def record_audit!(enrollment:, agent_snapshot:, agent_connection:, execution_runtime:)
      AuditLog.record!(
        installation: enrollment.installation,
        action: "agent_connection.registered",
        subject: agent_connection,
        metadata: {
          "agent_id" => agent_snapshot.agent_id,
          "agent_snapshot_id" => agent_snapshot.id,
          "execution_runtime_id" => execution_runtime&.id,
        }.compact
        )
    end

    def find_or_create_agent_snapshot!(agent:)
      existing = AgentSnapshot.find_by(installation: agent.installation, fingerprint: @fingerprint)
      return existing if existing.present?

      AgentSnapshot.create!(
        installation: agent.installation,
        agent: agent,
        fingerprint: @fingerprint,
        protocol_version: @protocol_version,
        sdk_version: @sdk_version,
        protocol_methods: @protocol_methods,
        tool_catalog: @tool_catalog,
        profile_catalog: @profile_catalog,
        config_schema_snapshot: @config_schema_snapshot,
        conversation_override_schema_snapshot: @conversation_override_schema_snapshot,
        default_config_snapshot: @default_config_snapshot
      )
    end
  end
end
