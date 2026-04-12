module ExecutionRuntimeVersions
  class Register
    Result = Struct.new(
      :pairing_session,
      :execution_runtime,
      :execution_runtime_version,
      :execution_runtime_connection,
      :execution_runtime_connection_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(pairing_token:, endpoint_metadata:, version_package:)
      @pairing_token = pairing_token
      @endpoint_metadata = normalize_hash(endpoint_metadata)
      @version_package = normalize_hash(version_package)
    end

    def call
      validate_endpoint_metadata!
      UpsertFromPackage.validate_package!(@version_package)
      pairing_session = PairingSessions::ResolveFromToken.call(pairing_token: @pairing_token)

      ApplicationRecord.transaction do
        execution_runtime = resolve_execution_runtime(pairing_session)
        upsert_result = UpsertFromPackage.call(
          execution_runtime: execution_runtime,
          version_package: @version_package
        )
        execution_runtime_version = upsert_result.execution_runtime_version

        execution_runtime.update!(
          kind: execution_runtime_version.kind,
          display_name: execution_runtime_version.reflected_host_metadata["display_name"].presence || execution_runtime.display_name,
          published_execution_runtime_version: execution_runtime_version,
          lifecycle_state: "active"
        )
        pairing_session.agent.update!(default_execution_runtime: execution_runtime)

        ExecutionRuntimeConnection.where(execution_runtime: execution_runtime, lifecycle_state: "active").update_all(
          lifecycle_state: "stale",
          updated_at: Time.current
        )

        plaintext_credential, credential_digest = ExecutionRuntimeConnection.issue_connection_credential
        _plaintext_token, token_digest = ExecutionRuntimeConnection.issue_connection_token
        execution_runtime_connection = ExecutionRuntimeConnection.create!(
          installation: pairing_session.installation,
          execution_runtime: execution_runtime,
          execution_runtime_version: execution_runtime_version,
          connection_credential_digest: credential_digest,
          connection_token_digest: token_digest,
          endpoint_metadata: @endpoint_metadata,
          lifecycle_state: "active",
          last_heartbeat_at: Time.current
        )

        PairingSessions::RecordProgress.call(
          pairing_session: pairing_session,
          runtime_registered: true
        )

        AuditLog.record!(
          installation: pairing_session.installation,
          action: "execution_runtime_connection.registered",
          subject: execution_runtime_connection,
          metadata: {
            "agent_id" => pairing_session.agent_id,
            "execution_runtime_id" => execution_runtime.id,
            "execution_runtime_version_id" => execution_runtime_version.id,
          }
        )

        Result.new(
          pairing_session: pairing_session,
          execution_runtime: execution_runtime,
          execution_runtime_version: execution_runtime_version,
          execution_runtime_connection: execution_runtime_connection,
          execution_runtime_connection_credential: plaintext_credential
        )
      end
    end

    private

    def validate_endpoint_metadata!
      return if @endpoint_metadata.is_a?(Hash)

      raise UpsertFromPackage::InvalidVersionPackage, "Endpoint metadata must be a Hash"
    end

    def resolve_execution_runtime(pairing_session)
      reflected_host_metadata = @version_package["reflected_host_metadata"]
      display_name =
        if reflected_host_metadata.is_a?(Hash)
          reflected_host_metadata["display_name"].presence
        end

      pairing_session.agent.default_execution_runtime ||
        ExecutionRuntime.create!(
          installation: pairing_session.installation,
          kind: @version_package.fetch("kind"),
          visibility: "public",
          provisioning_origin: "system",
          display_name: display_name || @version_package.fetch("execution_runtime_fingerprint"),
          lifecycle_state: "active"
        )
    end

    def normalize_hash(value)
      return {} if value.blank?
      return value.deep_stringify_keys if value.is_a?(Hash)

      value
    end
  end
end
