module AgentProgramVersions
  class Register
    InvalidEnrollment = Class.new(StandardError)
    ExpiredEnrollment = Class.new(StandardError)

    Result = Struct.new(
      :enrollment,
      :executor_program,
      :deployment,
      :agent_session,
      :executor_session,
      :session_credential,
      :executor_session_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      enrollment_token:,
      executor_fingerprint: nil,
      executor_kind: nil,
      executor_connection_metadata: nil,
      executor_capability_payload: nil,
      executor_tool_catalog: nil,
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
      @executor_fingerprint = executor_fingerprint
      @executor_kind = executor_kind || "local"
      @executor_connection_metadata = executor_connection_metadata || endpoint_metadata
      @executor_capability_payload = executor_capability_payload
      @executor_tool_catalog = executor_tool_catalog
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
        executor_program = register_executor_program(enrollment:)

        deployment = find_or_create_program_version!(agent_program: enrollment.agent_program)
        enrollment.agent_program.update!(default_executor_program: executor_program) if executor_program.present?

        AgentSession.where(agent_program: enrollment.agent_program, lifecycle_state: "active").update_all(
          lifecycle_state: "stale",
          updated_at: Time.current
        )
        stale_existing_executor_sessions!(executor_program:)

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

        executor_session, executor_session_credential = create_executor_session(enrollment:, executor_program:)

        enrollment.consume!
        record_audit!(enrollment:, deployment:, agent_session:, executor_program:)

        Result.new(
          enrollment: enrollment,
          executor_program: executor_program,
          deployment: deployment,
          agent_session: agent_session,
          executor_session: executor_session,
          session_credential: session_credential,
          executor_session_credential: executor_session_credential
        )
      end
    end

    private

    def register_executor_program(enrollment:)
      return nil if @executor_fingerprint.blank?

      executor_program = ExecutorPrograms::Reconcile.call(
        installation: enrollment.installation,
        executor_fingerprint: @executor_fingerprint,
        kind: @executor_kind,
        connection_metadata: @executor_connection_metadata
      )
      ExecutorPrograms::RecordCapabilities.call(
        executor_program: executor_program,
        capability_payload: @executor_capability_payload || {},
        tool_catalog: @executor_tool_catalog || []
      )
      executor_program
    end

    def stale_existing_executor_sessions!(executor_program:)
      return if executor_program.blank?

      ExecutorSession.where(executor_program: executor_program, lifecycle_state: "active").update_all(
        lifecycle_state: "stale",
        updated_at: Time.current
      )
    end

    def create_executor_session(enrollment:, executor_program:)
      return [nil, nil] if executor_program.blank?

      execution_credential, execution_credential_digest = ExecutorSession.issue_session_credential
      _execution_token, session_token_digest = ExecutorSession.issue_session_token
      executor_session = ExecutorSession.create!(
        installation: enrollment.installation,
        executor_program: executor_program,
        session_credential_digest: execution_credential_digest,
        session_token_digest: session_token_digest,
        endpoint_metadata: @executor_connection_metadata,
        lifecycle_state: "active"
      )
      [executor_session, execution_credential]
    end

    def record_audit!(enrollment:, deployment:, agent_session:, executor_program:)
      AuditLog.record!(
        installation: enrollment.installation,
        action: "agent_session.registered",
        subject: agent_session,
        metadata: {
          "agent_program_id" => deployment.agent_program_id,
          "agent_program_version_id" => deployment.id,
          "executor_program_id" => executor_program&.id,
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
