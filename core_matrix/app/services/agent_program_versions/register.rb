module AgentProgramVersions
  class Register
    InvalidEnrollment = Class.new(StandardError)
    ExpiredEnrollment = Class.new(StandardError)

    Result = Struct.new(
      :enrollment,
      :execution_runtime,
      :deployment,
      :agent_session,
      :execution_session,
      :session_credential,
      :execution_session_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      enrollment_token:,
      runtime_fingerprint: nil,
      runtime_kind: nil,
      runtime_connection_metadata: nil,
      execution_capability_payload: nil,
      execution_tool_catalog: nil,
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
      @runtime_fingerprint = runtime_fingerprint
      @runtime_kind = runtime_kind || "local"
      @runtime_connection_metadata = runtime_connection_metadata || endpoint_metadata
      @execution_capability_payload = execution_capability_payload
      @execution_tool_catalog = execution_tool_catalog
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
      raise InvalidEnrollment, "enrollment token is invalid" if enrollment.blank? || enrollment.consumed?
      raise ExpiredEnrollment, "enrollment token has expired" if enrollment.expired?

      ApplicationRecord.transaction do
        execution_runtime = register_execution_runtime(enrollment:)

        deployment = find_or_create_program_version!(agent_program: enrollment.agent_program)
        enrollment.agent_program.update!(default_execution_runtime: execution_runtime) if execution_runtime.present?

        AgentSession.where(agent_program: enrollment.agent_program, lifecycle_state: "active").update_all(
          lifecycle_state: "stale",
          updated_at: Time.current
        )
        stale_existing_execution_sessions!(execution_runtime:)

        session_credential, session_credential_digest = AgentSession.issue_session_credential
        session_token, session_token_digest = AgentSession.issue_session_token
        agent_session = AgentSession.create!(
          installation: enrollment.installation,
          agent_program: enrollment.agent_program,
          agent_program_version: deployment,
          session_credential_digest: session_credential_digest,
          session_token_digest: session_token_digest,
          endpoint_metadata: @endpoint_metadata,
          lifecycle_state: "active",
          health_status: "pending",
          health_metadata: {},
          auto_resume_eligible: false,
          last_heartbeat_at: Time.current
        )

        execution_session, execution_session_credential = create_execution_session(enrollment:, execution_runtime:)

        enrollment.consume!
        record_audit!(enrollment:, deployment:, agent_session:, execution_runtime:)

        Result.new(
          enrollment: enrollment,
          execution_runtime: execution_runtime,
          deployment: deployment,
          agent_session: agent_session,
          execution_session: execution_session,
          session_credential: session_credential,
          execution_session_credential: execution_session_credential
        )
      end
    end

    private

    def register_execution_runtime(enrollment:)
      return nil if @runtime_fingerprint.blank?

      execution_runtime = ExecutionRuntimes::Reconcile.call(
        installation: enrollment.installation,
        runtime_fingerprint: @runtime_fingerprint,
        kind: @runtime_kind,
        connection_metadata: @runtime_connection_metadata
      )
      ExecutionRuntimes::RecordCapabilities.call(
        execution_runtime: execution_runtime,
        capability_payload: @execution_capability_payload || {},
        tool_catalog: @execution_tool_catalog || []
      )
      execution_runtime
    end

    def stale_existing_execution_sessions!(execution_runtime:)
      return if execution_runtime.blank?

      ExecutionSession.where(execution_runtime: execution_runtime, lifecycle_state: "active").update_all(
        lifecycle_state: "stale",
        updated_at: Time.current
      )
    end

    def create_execution_session(enrollment:, execution_runtime:)
      return [nil, nil] if execution_runtime.blank?

      execution_credential, execution_credential_digest = ExecutionSession.issue_session_credential
      execution_token, execution_token_digest = ExecutionSession.issue_session_token
      execution_session = ExecutionSession.create!(
        installation: enrollment.installation,
        execution_runtime: execution_runtime,
        session_credential_digest: execution_credential_digest,
        session_token_digest: execution_token_digest,
        endpoint_metadata: @runtime_connection_metadata,
        lifecycle_state: "active"
      )
      [execution_session, execution_credential]
    end

    def record_audit!(enrollment:, deployment:, agent_session:, execution_runtime:)
      AuditLog.record!(
        installation: enrollment.installation,
        action: "agent_session.registered",
        subject: agent_session,
        metadata: {
          "agent_program_id" => deployment.agent_program_id,
          "agent_program_version_id" => deployment.id,
          "execution_runtime_id" => execution_runtime&.id,
        }.compact
      )
    end

    def find_or_create_program_version!(agent_program:)
      existing = AgentProgramVersion.find_by(installation: agent_program.installation, fingerprint: @fingerprint)
      return existing if existing.present?

      AgentProgramVersion.create!(
        installation: agent_program.installation,
        agent_program: agent_program,
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
