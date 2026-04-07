module Installations
  class RegisterBundledAgentRuntime
    DEFAULT_CONFIGURATION = {
      enabled: false,
      agent_key: "fenix",
      display_name: "Bundled Fenix",
      visibility: "global",
      lifecycle_state: "active",
      executor_kind: "local",
      executor_fingerprint: "bundled-fenix-environment",
      executor_display_name: "Bundled Fenix Runtime",
      connection_metadata: {},
      endpoint_metadata: {},
      executor_capability_payload: {},
      executor_tool_catalog: [],
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
      :agent_program,
      :executor_program,
      :deployment,
      :capability_snapshot,
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
      installation:,
      configuration: Rails.configuration.x.bundled_agent,
      session_credential: nil,
      executor_session_credential: nil,
      execution_session_credential: nil
    )
      @installation = installation
      @configuration = normalize_configuration(configuration)
      @session_credential = session_credential
      @executor_session_credential = executor_session_credential || execution_session_credential
    end

    def call
      return unless @configuration[:enabled]

      ApplicationRecord.transaction do
        executor_program = reconcile_executor_program!
        agent_program = reconcile_agent_program!(executor_program)
        deployment = nil
        agent_session = nil
        executor_session = nil
        session_credential = nil
        executor_session_credential = nil

        agent_program.with_lock do
          executor_program.with_lock do
            deployment = reconcile_deployment!(agent_program)
            agent_session, session_credential = reconcile_agent_session!(agent_program:, deployment:)
            executor_session, executor_session_credential = reconcile_executor_session!(executor_program:)
          end
        end

        agent_program.reload
        executor_program.reload
        deployment.reload

        Result.new(
          agent_program:,
          executor_program:,
          deployment:,
          capability_snapshot: deployment,
          agent_session:,
          executor_session:,
          session_credential:,
          executor_session_credential:
        )
      end
    end

    private

    def normalize_configuration(configuration)
      values = configuration.respond_to?(:to_h) ? configuration.to_h : configuration
      values.each_with_object(DEFAULT_CONFIGURATION.dup) do |(key, value), normalized|
        normalized[key.to_sym] = value
      end
        .tap do |normalized|
          normalized[:executor_kind] = normalized[:runtime_kind] if normalized[:runtime_kind].present?
          normalized[:executor_fingerprint] = normalized[:runtime_fingerprint] if normalized[:runtime_fingerprint].present?
          normalized[:executor_display_name] = normalized[:runtime_display_name] if normalized[:runtime_display_name].present?
          normalized[:executor_capability_payload] = normalized[:execution_capability_payload] if normalized.key?(:execution_capability_payload)
          normalized[:executor_tool_catalog] = normalized[:execution_tool_catalog] if normalized.key?(:execution_tool_catalog)
        end
    end

    def reconcile_agent_program!(executor_program)
      agent_program = AgentProgram.find_or_initialize_by(
        installation: @installation,
        key: @configuration[:agent_key]
      )
      agent_program.update!(
        display_name: @configuration[:display_name],
        visibility: @configuration[:visibility],
        lifecycle_state: @configuration[:lifecycle_state],
        owner_user: nil,
        default_executor_program: executor_program
      )
      agent_program
    end

    def reconcile_executor_program!
      executor_program = ExecutorPrograms::Reconcile.call(
        installation: @installation,
        executor_fingerprint: @configuration[:executor_fingerprint],
        kind: @configuration[:executor_kind],
        connection_metadata: @configuration[:connection_metadata]
      )
      executor_program.update!(display_name: @configuration[:executor_display_name])
      ExecutorPrograms::RecordCapabilities.call(
        executor_program: executor_program,
        capability_payload: @configuration[:executor_capability_payload],
        tool_catalog: @configuration[:executor_tool_catalog]
      )
      executor_program
    end

    def reconcile_deployment!(agent_program)
      deployment = AgentProgramVersion.find_by(
        installation: @installation,
        fingerprint: @configuration[:fingerprint]
      )
      return deployment if deployment.present?

      AgentProgramVersion.create!(
        installation: @installation,
        agent_program: agent_program,
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
      AgentProgramVersion.find_by!(
        installation: @installation,
        fingerprint: @configuration[:fingerprint]
      )
    end

    def reconcile_agent_session!(agent_program:, deployment:)
      active_session = agent_program.active_agent_session
      if active_session&.agent_program_version_id == deployment.id
        return refresh_agent_session!(active_session, deployment)
      end

      AgentSession.where(agent_program:, lifecycle_state: "active").update_all(
        lifecycle_state: "stale",
        updated_at: Time.current
      )
      create_agent_session!(agent_program:, deployment:)
    end

    def refresh_agent_session!(agent_session, deployment)
      session_credential = @session_credential
      if session_credential.present?
        agent_session.assign_attributes(
          session_credential_digest: AgentSession.digest_session_credential(session_credential)
        )
      end

      agent_session.update!(
        agent_program_version: deployment,
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        health_status: "healthy",
        health_metadata: { "source" => "bundled_runtime" },
        auto_resume_eligible: true,
        unavailability_reason: nil,
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current
      )
      [agent_session, session_credential]
    end

    def create_agent_session!(agent_program:, deployment:)
      session_credential = @session_credential.presence
      session_credential_digest =
        if session_credential.present?
          AgentSession.digest_session_credential(session_credential)
        else
          session_credential, digest = AgentSession.issue_session_credential
          digest
        end
      session_token, session_token_digest = AgentSession.issue_session_token
      agent_session = AgentSession.create!(
        installation: @installation,
        agent_program: agent_program,
        agent_program_version: deployment,
        session_credential_digest: session_credential_digest,
        session_token_digest: session_token_digest,
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        health_status: "healthy",
        health_metadata: { "source" => "bundled_runtime" },
        auto_resume_eligible: true,
        unavailability_reason: nil,
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current
      )
      [agent_session, session_credential]
    end

    def reconcile_executor_session!(executor_program:)
      active_session = executor_program.active_executor_session
      return refresh_executor_session!(active_session) if active_session.present?

      ExecutorSession.where(executor_program:, lifecycle_state: "active").update_all(
        lifecycle_state: "stale",
        updated_at: Time.current
      )
      create_executor_session!(executor_program:)
    end

    def refresh_executor_session!(executor_session)
      session_credential = @executor_session_credential
      if session_credential.present?
        executor_session.assign_attributes(
          session_credential_digest: ExecutorSession.digest_session_credential(session_credential)
        )
      end

      executor_session.update!(
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        last_heartbeat_at: Time.current
      )
      [executor_session, session_credential]
    end

    def create_executor_session!(executor_program:)
      session_credential = @executor_session_credential.presence
      session_credential_digest =
        if session_credential.present?
          ExecutorSession.digest_session_credential(session_credential)
        else
          session_credential, digest = ExecutorSession.issue_session_credential
          digest
        end
      session_token, session_token_digest = ExecutorSession.issue_session_token
      executor_session = ExecutorSession.create!(
        installation: @installation,
        executor_program: executor_program,
        session_credential_digest: session_credential_digest,
        session_token_digest: session_token_digest,
        endpoint_metadata: @configuration[:endpoint_metadata],
        lifecycle_state: "active",
        last_heartbeat_at: Time.current
      )
      [executor_session, session_credential]
    end
  end
end
