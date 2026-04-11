module Installations
  class RegisterBundledAgentRuntime
    DEFAULT_CONFIGURATION = {
      enabled: false,
      agent_key: "fenix",
      display_name: "Bundled Fenix",
      visibility: "public",
      provisioning_origin: "system",
      lifecycle_state: "active",
      execution_runtime_kind: "local",
      execution_runtime_fingerprint: "bundled-fenix-environment",
      executor_display_name: "Bundled Fenix Runtime",
      connection_metadata: {},
      endpoint_metadata: {},
      execution_runtime_capability_payload: {},
      execution_runtime_tool_catalog: [],
      fingerprint: "bundled-fenix-runtime",
      protocol_version: "2026-03-24",
      sdk_version: "fenix-0.1.0",
      protocol_methods: [],
      tool_catalog: [],
      profile_catalog: {},
      config_schema_snapshot: {},
      conversation_override_schema_snapshot: {},
      default_config_snapshot: {},
    }.freeze

    Result = Struct.new(
      :agent,
      :execution_runtime,
      :agent_snapshot,
      :capability_snapshot,
      :agent_connection,
      :execution_runtime_connection,
      :agent_connection_credential,
      :execution_runtime_connection_credential,
      keyword_init: true
    )

    def self.call(...)
      new(...).call
    end

    def initialize(
      installation:,
      configuration: Rails.configuration.x.bundled_agent,
      agent_connection_credential: nil,
      execution_runtime_connection_credential: nil
    )
      @installation = installation
      @configuration = normalize_configuration(configuration)
      @agent_connection_credential = agent_connection_credential
      @execution_runtime_connection_credential = execution_runtime_connection_credential
    end

    def call
      return unless @configuration[:enabled]

      ApplicationRecord.transaction do
        execution_runtime = reconcile_execution_runtime!
        agent = reconcile_agent!(execution_runtime)
        agent_snapshot = nil
        agent_connection = nil
        execution_runtime_connection = nil
        agent_connection_credential = nil
        execution_runtime_connection_credential = nil

        agent.with_lock do
          execution_runtime.with_lock do
            agent_snapshot = reconcile_agent_snapshot!(agent)
            agent_connection, agent_connection_credential = reconcile_agent_connection!(agent:, agent_snapshot:)
            execution_runtime_connection, execution_runtime_connection_credential = reconcile_execution_runtime_connection!(execution_runtime:)
          end
        end

        agent.reload
        execution_runtime.reload
        agent_snapshot.reload

        Result.new(
          agent:,
          execution_runtime:,
          agent_snapshot:,
          capability_snapshot: agent_snapshot,
          agent_connection:,
          execution_runtime_connection:,
          agent_connection_credential:,
          execution_runtime_connection_credential:
        )
      end
    end

    private

    def normalize_configuration(configuration)
      values = configuration.respond_to?(:to_h) ? configuration.to_h : configuration
      values.each_with_object(DEFAULT_CONFIGURATION.dup) do |(key, value), normalized|
        normalized[key.to_sym] = value
      end
    end

    def reconcile_agent!(execution_runtime)
      agent = Agent.find_or_initialize_by(
        installation: @installation,
        key: @configuration[:agent_key]
      )
      agent.update!(
        display_name: @configuration[:display_name],
        visibility: @configuration[:visibility],
        provisioning_origin: @configuration[:provisioning_origin],
        lifecycle_state: @configuration[:lifecycle_state],
        owner_user: nil,
        default_execution_runtime: execution_runtime
      )
      agent
    end

    def reconcile_execution_runtime!
      execution_runtime = ExecutionRuntimes::Reconcile.call(
        installation: @installation,
        execution_runtime_fingerprint: @configuration[:execution_runtime_fingerprint],
        kind: @configuration[:execution_runtime_kind],
        connection_metadata: @configuration[:connection_metadata]
      )
      execution_runtime.update!(
        display_name: @configuration[:executor_display_name],
        visibility: "public",
        provisioning_origin: "system",
        owner_user: nil
      )
      ExecutionRuntimes::RecordCapabilities.call(
        execution_runtime: execution_runtime,
        capability_payload: @configuration[:execution_runtime_capability_payload],
        tool_catalog: @configuration[:execution_runtime_tool_catalog]
      )
      execution_runtime
    end

    def reconcile_agent_snapshot!(agent)
      agent_snapshot = AgentSnapshot.find_by(
        installation: @installation,
        fingerprint: @configuration[:fingerprint]
      )
      return agent_snapshot if agent_snapshot.present?

      AgentSnapshot.create!(
        installation: @installation,
        agent: agent,
        fingerprint: @configuration[:fingerprint],
        protocol_version: @configuration[:protocol_version],
        sdk_version: @configuration[:sdk_version],
        protocol_methods: @configuration[:protocol_methods],
        tool_catalog: @configuration[:tool_catalog],
        profile_catalog: @configuration[:profile_catalog],
        config_schema_snapshot: @configuration[:config_schema_snapshot],
        conversation_override_schema_snapshot: @configuration[:conversation_override_schema_snapshot],
        default_config_snapshot: @configuration[:default_config_snapshot]
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      AgentSnapshot.find_by!(
        installation: @installation,
        fingerprint: @configuration[:fingerprint]
      )
    end

    def reconcile_agent_connection!(agent:, agent_snapshot:)
      active_session = agent.active_agent_connection
      if active_session&.agent_snapshot_id == agent_snapshot.id
        return refresh_agent_connection!(active_session, agent_snapshot)
      end

      AgentConnection.where(agent:, lifecycle_state: "active").update_all(
        lifecycle_state: "stale",
        updated_at: Time.current
      )
      create_agent_connection!(agent:, agent_snapshot:)
    end

    def refresh_agent_connection!(agent_connection, agent_snapshot)
      agent_connection_credential = @agent_connection_credential
      if agent_connection_credential.present?
        agent_connection.assign_attributes(
          connection_credential_digest: AgentConnection.digest_connection_credential(agent_connection_credential)
        )
      end

      agent_connection.update!(
        agent_snapshot: agent_snapshot,
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        health_status: "healthy",
        health_metadata: { "source" => "bundled_runtime" },
        auto_resume_eligible: true,
        unavailability_reason: nil,
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current
      )
      [agent_connection, agent_connection_credential]
    end

    def create_agent_connection!(agent:, agent_snapshot:)
      agent_connection_credential = @agent_connection_credential.presence
      connection_credential_digest =
        if agent_connection_credential.present?
          AgentConnection.digest_connection_credential(agent_connection_credential)
        else
          agent_connection_credential, digest = AgentConnection.issue_connection_credential
          digest
        end
      _connection_token, connection_token_digest = AgentConnection.issue_connection_token
      agent_connection = AgentConnection.create!(
        installation: @installation,
        agent: agent,
        agent_snapshot: agent_snapshot,
        connection_credential_digest: connection_credential_digest,
        connection_token_digest: connection_token_digest,
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        health_status: "healthy",
        health_metadata: { "source" => "bundled_runtime" },
        auto_resume_eligible: true,
        unavailability_reason: nil,
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current
      )
      [agent_connection, agent_connection_credential]
    end

    def reconcile_execution_runtime_connection!(execution_runtime:)
      active_session = execution_runtime.active_execution_runtime_connection
      return refresh_execution_runtime_connection!(active_session) if active_session.present?

      ExecutionRuntimeConnection.where(execution_runtime:, lifecycle_state: "active").update_all(
        lifecycle_state: "stale",
        updated_at: Time.current
      )
      create_execution_runtime_connection!(execution_runtime:)
    end

    def refresh_execution_runtime_connection!(execution_runtime_connection)
      runtime_connection_credential = @execution_runtime_connection_credential
      if runtime_connection_credential.present?
        execution_runtime_connection.assign_attributes(
          connection_credential_digest: ExecutionRuntimeConnection.digest_connection_credential(runtime_connection_credential)
        )
      end

      execution_runtime_connection.update!(
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        last_heartbeat_at: Time.current
      )
      [execution_runtime_connection, runtime_connection_credential]
    end

    def create_execution_runtime_connection!(execution_runtime:)
      runtime_connection_credential = @execution_runtime_connection_credential.presence
      connection_credential_digest =
        if runtime_connection_credential.present?
          ExecutionRuntimeConnection.digest_connection_credential(runtime_connection_credential)
        else
          runtime_connection_credential, digest = ExecutionRuntimeConnection.issue_connection_credential
          digest
        end
      _connection_token, connection_token_digest = ExecutionRuntimeConnection.issue_connection_token
      execution_runtime_connection = ExecutionRuntimeConnection.create!(
        installation: @installation,
        execution_runtime: execution_runtime,
        connection_credential_digest: connection_credential_digest,
        connection_token_digest: connection_token_digest,
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        last_heartbeat_at: Time.current
      )
      [execution_runtime_connection, runtime_connection_credential]
    end
  end
end
