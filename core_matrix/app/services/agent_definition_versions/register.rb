module AgentDefinitionVersions
  class Register
    Result = Struct.new(
      :onboarding_session,
      :execution_runtime,
      :agent_definition_version,
      :agent_config_state,
      :agent_connection,
      :agent_connection_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(onboarding_token:, endpoint_metadata:, definition_package:)
      @onboarding_token = onboarding_token
      @endpoint_metadata = normalize_hash(endpoint_metadata)
      @definition_package = normalize_hash(definition_package)
    end

    def call
      validate_endpoint_metadata!
      UpsertFromPackage.validate_package!(@definition_package)
      onboarding_session = OnboardingSessions::ResolveFromToken.call(
        onboarding_token: @onboarding_token,
        target_kind: "agent"
      )
      agent = onboarding_session.target_agent

      ApplicationRecord.transaction do
        upsert_result = UpsertFromPackage.call(
          agent: agent,
          definition_package: @definition_package
        )
        agent_definition_version = upsert_result.agent_definition_version
        agent_config_state = AgentConfigStates::Reconcile.call(
          agent: agent,
          agent_definition_version: agent_definition_version
        )

        agent.update!(
          current_agent_definition_version: agent_definition_version,
          published_agent_definition_version: agent_definition_version
        )

        AgentConnection.where(agent: agent, lifecycle_state: "active").update_all(
          lifecycle_state: "stale",
          updated_at: Time.current
        )

        plaintext_credential, credential_digest = AgentConnection.issue_connection_credential
        _plaintext_token, token_digest = AgentConnection.issue_connection_token
        agent_connection = AgentConnection.create!(
          installation: onboarding_session.installation,
          agent: agent,
          agent_definition_version: agent_definition_version,
          connection_credential_digest: credential_digest,
          connection_token_digest: token_digest,
          endpoint_metadata: @endpoint_metadata,
          lifecycle_state: "active",
          health_status: "pending",
          health_metadata: {},
          auto_resume_eligible: false,
          last_heartbeat_at: Time.current
        )

        OnboardingSessions::RecordProgress.call(
          onboarding_session: onboarding_session,
          agent_registered: true
        )

        AuditLog.record!(
          installation: onboarding_session.installation,
          action: "agent_connection.registered",
          subject: agent_connection,
          metadata: {
            "agent_id" => agent.id,
            "agent_definition_version_id" => agent_definition_version.id,
            "execution_runtime_id" => agent.default_execution_runtime_id,
          }.compact
        )

        Result.new(
          onboarding_session: onboarding_session,
          execution_runtime: agent.default_execution_runtime,
          agent_definition_version: agent_definition_version,
          agent_config_state: agent_config_state,
          agent_connection: agent_connection,
          agent_connection_credential: plaintext_credential
        )
      end
    end

    private

    def validate_endpoint_metadata!
      return if @endpoint_metadata.is_a?(Hash)

      raise UpsertFromPackage::InvalidDefinitionPackage, "Endpoint metadata must be a Hash"
    end

    def normalize_hash(value)
      return {} if value.blank?
      return value.deep_stringify_keys if value.is_a?(Hash)

      value
    end
  end
end
