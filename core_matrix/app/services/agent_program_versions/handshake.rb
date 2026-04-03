module AgentProgramVersions
  class Handshake
    FingerprintMismatch = Class.new(StandardError)

    Result = Struct.new(
      :deployment,
      :reconciliation_report,
      :runtime_capability_contract,
      keyword_init: true
    ) do
      def capability_snapshot
        deployment
      end
    end

    def self.call(...)
      new(...).call
    end

    def initialize(
      agent_session: nil,
      deployment:,
      execution_runtime: nil,
      fingerprint:,
      protocol_version:,
      sdk_version:,
      execution_capability_payload: nil,
      execution_tool_catalog: nil,
      protocol_methods:,
      tool_catalog:,
      profile_catalog:,
      config_schema_snapshot:,
      conversation_override_schema_snapshot:,
      default_config_snapshot:
    )
      @agent_session = agent_session
      @deployment = deployment
      @execution_runtime = execution_runtime
      @fingerprint = fingerprint
      @protocol_version = protocol_version
      @sdk_version = sdk_version
      @execution_capability_payload = execution_capability_payload
      @execution_tool_catalog = execution_tool_catalog
      @protocol_methods = protocol_methods
      @tool_catalog = tool_catalog
      @profile_catalog = profile_catalog
      @config_schema_snapshot = config_schema_snapshot
      @conversation_override_schema_snapshot = conversation_override_schema_snapshot
      @default_config_snapshot = default_config_snapshot
    end

    def call
      raise FingerprintMismatch, "deployment fingerprint does not match the authenticated deployment" if @deployment.fingerprint != @fingerprint

      candidate = AgentProgramVersion.new(
        installation: @deployment.installation,
        agent_program: @deployment.agent_program,
        fingerprint: @deployment.fingerprint,
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

      if @execution_runtime.present? && (!@execution_capability_payload.nil? || !@execution_tool_catalog.nil?)
        ExecutionRuntimes::RecordCapabilities.call(
          execution_runtime: @execution_runtime,
          capability_payload: @execution_capability_payload || @execution_runtime.capability_payload,
          tool_catalog: @execution_tool_catalog || @execution_runtime.tool_catalog
        )
      end

      runtime_capability_contract = RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime || @deployment.agent_program.default_execution_runtime,
        agent_program_version: @deployment
      )

      ToolBindings::ProjectCapabilitySnapshot.call(
        agent_program_version: @deployment,
        execution_runtime: @execution_runtime || @deployment.agent_program.default_execution_runtime
      )

      Result.new(
        deployment: @deployment,
        reconciliation_report: {},
        runtime_capability_contract: runtime_capability_contract
      )
    end
  end
end
