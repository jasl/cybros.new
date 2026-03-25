module Installations
  class RegisterBundledAgentRuntime
    DEFAULT_CONFIGURATION = {
      enabled: false,
      agent_key: "fenix",
      display_name: "Bundled Fenix",
      visibility: "global",
      lifecycle_state: "active",
      environment_kind: "local",
      connection_metadata: {},
      fingerprint: "bundled-fenix-runtime",
      protocol_version: "2026-03-24",
      sdk_version: "fenix-0.1.0",
      protocol_methods: [],
      tool_catalog: [],
      config_schema_snapshot: {},
      conversation_override_schema_snapshot: {},
      default_config_snapshot: {},
    }.freeze

    Result = Struct.new(:agent_installation, :execution_environment, :deployment, :capability_snapshot, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(installation:, configuration: Rails.configuration.x.bundled_agent)
      @installation = installation
      @configuration = normalize_configuration(configuration)
    end

    def call
      return unless @configuration[:enabled]

      ApplicationRecord.transaction do
        agent_installation = reconcile_agent_installation!
        execution_environment = reconcile_execution_environment!
        deployment = reconcile_deployment!(agent_installation, execution_environment)
        capability_snapshot = reconcile_capability_snapshot!(deployment)

        Result.new(
          agent_installation: agent_installation,
          execution_environment: execution_environment,
          deployment: deployment,
          capability_snapshot: capability_snapshot
        )
      end
    end

    private

    def normalize_configuration(configuration)
      values = configuration.respond_to?(:to_h) ? configuration.to_h : configuration
      values = values.each_with_object({}) do |(key, value), normalized|
        normalized[key.to_sym] = value
      end

      DEFAULT_CONFIGURATION.merge(values)
    end

    def reconcile_agent_installation!
      agent_installation = AgentInstallation.find_or_initialize_by(
        installation: @installation,
        key: @configuration[:agent_key]
      )
      agent_installation.update!(
        display_name: @configuration[:display_name],
        visibility: @configuration[:visibility],
        lifecycle_state: @configuration[:lifecycle_state],
        owner_user: nil
      )
      agent_installation
    end

    def reconcile_execution_environment!
      execution_environment = ExecutionEnvironment.find_or_initialize_by(
        installation: @installation,
        kind: @configuration[:environment_kind]
      )
      execution_environment.update!(
        connection_metadata: @configuration[:connection_metadata],
        lifecycle_state: "active"
      )
      execution_environment
    end

    def reconcile_deployment!(agent_installation, execution_environment)
      deployment = find_existing_deployment(agent_installation) || AgentDeployment.new(installation: @installation)
      deployment.assign_attributes(
        agent_installation: agent_installation,
        execution_environment: execution_environment,
        fingerprint: @configuration[:fingerprint],
        endpoint_metadata: @configuration[:connection_metadata],
        protocol_version: @configuration[:protocol_version],
        sdk_version: @configuration[:sdk_version],
        machine_credential_digest: bundled_machine_credential_digest,
        health_status: "healthy",
        health_metadata: { "source" => "bundled_runtime" },
        last_heartbeat_at: Time.current,
        last_health_check_at: Time.current,
        unavailability_reason: nil,
        auto_resume_eligible: true,
        bootstrap_state: "active"
      )
      deployment.save!
      deployment
    end

    def reconcile_capability_snapshot!(deployment)
      deployment.with_lock do
        deployment.reload

        existing_snapshot = matching_capability_snapshot(deployment)
        if existing_snapshot.present?
          deployment.update!(active_capability_snapshot: existing_snapshot) if deployment.active_capability_snapshot != existing_snapshot
          return existing_snapshot
        end

        version = deployment.capability_snapshots.maximum(:version).to_i + 1
        capability_snapshot = deployment.capability_snapshots.create!(
          version: version,
          protocol_methods: @configuration[:protocol_methods],
          tool_catalog: @configuration[:tool_catalog],
          config_schema_snapshot: @configuration[:config_schema_snapshot],
          conversation_override_schema_snapshot: @configuration[:conversation_override_schema_snapshot],
          default_config_snapshot: @configuration[:default_config_snapshot]
        )
        deployment.update!(active_capability_snapshot: capability_snapshot)
        capability_snapshot
      end
    end

    def find_existing_deployment(agent_installation)
      AgentDeployment.find_by(installation: @installation, fingerprint: @configuration[:fingerprint]) ||
        AgentDeployment.find_by(agent_installation: agent_installation, bootstrap_state: "active")
    end

    def bundled_machine_credential_digest
      AgentDeployment.digest_machine_credential("bundled-runtime:#{@configuration[:fingerprint]}")
    end

    def matching_capability_snapshot(deployment)
      deployment.capability_snapshots.detect do |snapshot|
        snapshot.protocol_methods == @configuration[:protocol_methods] &&
          snapshot.tool_catalog == @configuration[:tool_catalog] &&
          snapshot.config_schema_snapshot == @configuration[:config_schema_snapshot] &&
          snapshot.conversation_override_schema_snapshot == @configuration[:conversation_override_schema_snapshot] &&
          snapshot.default_config_snapshot == @configuration[:default_config_snapshot]
      end
    end
  end
end
