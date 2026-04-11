module AgentSnapshots
  class Handshake
    FingerprintMismatch = Class.new(StandardError)

    Result = Struct.new(
      :agent_snapshot,
      :reconciliation_report,
      :runtime_capability_contract,
      keyword_init: true
    ) do
      def capability_snapshot
        agent_snapshot
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(
      agent_connection: nil,
      agent_snapshot:,
      execution_runtime: nil,
      fingerprint:,
      protocol_version:,
      sdk_version:,
      protocol_methods:,
      tool_catalog:,
      profile_catalog:,
      config_schema_snapshot:,
      conversation_override_schema_snapshot:,
      default_config_snapshot:
    )
      @agent_connection = agent_connection
      @agent_snapshot = agent_snapshot
      @execution_runtime = execution_runtime
      @fingerprint = fingerprint
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
      raise FingerprintMismatch, "agent snapshot fingerprint does not match the authenticated agent snapshot" if @agent_snapshot.fingerprint != @fingerprint

      candidate = AgentSnapshot.new(
        installation: @agent_snapshot.installation,
        agent: @agent_snapshot.agent,
        fingerprint: @agent_snapshot.fingerprint,
        protocol_version: @protocol_version,
        sdk_version: @sdk_version,
        protocol_methods: @protocol_methods,
        tool_catalog: @tool_catalog,
        profile_catalog: @profile_catalog,
        config_schema_snapshot: @config_schema_snapshot,
        conversation_override_schema_snapshot: @conversation_override_schema_snapshot,
        default_config_snapshot: @default_config_snapshot
      )
      candidate.valid?
      candidate.errors.delete(:fingerprint)
      raise ActiveRecord::RecordInvalid, candidate if candidate.errors.any?

      runtime_capability_contract = RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime || @agent_snapshot.agent.default_execution_runtime,
        agent_snapshot: @agent_snapshot
      )

      ToolBindings::ProjectCapabilitySnapshot.call(
        agent_snapshot: @agent_snapshot,
        execution_runtime: @execution_runtime || @agent_snapshot.agent.default_execution_runtime
      )

      Result.new(
        agent_snapshot: @agent_snapshot,
        reconciliation_report: {},
        runtime_capability_contract: runtime_capability_contract
      )
    end
  end
end
