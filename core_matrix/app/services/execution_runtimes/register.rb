module ExecutionRuntimes
  class Register
    InvalidEnrollment = Class.new(StandardError)
    ExpiredEnrollment = Class.new(StandardError)

    Result = Struct.new(
      :enrollment,
      :execution_runtime,
      :execution_runtime_connection,
      :execution_runtime_connection_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      enrollment_token:,
      execution_runtime_fingerprint:,
      execution_runtime_kind:,
      execution_runtime_connection_metadata:,
      execution_runtime_capability_payload:,
      execution_runtime_tool_catalog:
    )
      @enrollment_token = enrollment_token
      @execution_runtime_fingerprint = execution_runtime_fingerprint
      @execution_runtime_kind = execution_runtime_kind || "local"
      @execution_runtime_connection_metadata = execution_runtime_connection_metadata || {}
      @execution_runtime_capability_payload = execution_runtime_capability_payload || {}
      @execution_runtime_tool_catalog = execution_runtime_tool_catalog || []
    end

    def call
      enrollment = AgentEnrollment.find_by_plaintext_token(@enrollment_token)
      raise InvalidEnrollment, "enrollment token is invalid" if enrollment.blank?
      raise ExpiredEnrollment, "enrollment token has expired" if enrollment.expired?

      ApplicationRecord.transaction do
        execution_runtime = ExecutionRuntimes::Reconcile.call(
          installation: enrollment.installation,
          execution_runtime_fingerprint: @execution_runtime_fingerprint,
          kind: @execution_runtime_kind,
          connection_metadata: @execution_runtime_connection_metadata
        )
        ExecutionRuntimes::RecordCapabilities.call(
          execution_runtime: execution_runtime,
          capability_payload: @execution_runtime_capability_payload,
          tool_catalog: @execution_runtime_tool_catalog
        )
        enrollment.agent.update!(default_execution_runtime: execution_runtime)

        ExecutionRuntimeConnection.where(execution_runtime:, lifecycle_state: "active").update_all(
          lifecycle_state: "stale",
          updated_at: Time.current
        )

        plaintext_credential, credential_digest = ExecutionRuntimeConnection.issue_connection_credential
        _plaintext_token, token_digest = ExecutionRuntimeConnection.issue_connection_token
        execution_runtime_connection = ExecutionRuntimeConnection.create!(
          installation: enrollment.installation,
          execution_runtime: execution_runtime,
          connection_credential_digest: credential_digest,
          connection_token_digest: token_digest,
          endpoint_metadata: @execution_runtime_connection_metadata,
          lifecycle_state: "active",
          last_heartbeat_at: Time.current
        )

        AuditLog.record!(
          installation: enrollment.installation,
          action: "execution_runtime_connection.registered",
          subject: execution_runtime_connection,
          metadata: {
            "agent_id" => enrollment.agent_id,
            "execution_runtime_id" => execution_runtime.id,
          }
        )

        Result.new(
          enrollment: enrollment,
          execution_runtime: execution_runtime,
          execution_runtime_connection: execution_runtime_connection,
          execution_runtime_connection_credential: plaintext_credential
        )
      end
    end
  end
end
