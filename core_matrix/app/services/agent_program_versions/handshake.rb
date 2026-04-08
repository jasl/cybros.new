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
      executor_program: nil,
      fingerprint:,
      protocol_version:,
      sdk_version:,
      executor_capability_payload: nil,
      executor_tool_catalog: nil,
      protocol_methods:,
      tool_catalog:,
      profile_catalog:,
      config_schema_snapshot:,
      conversation_override_schema_snapshot:,
      default_config_snapshot:
    )
      @agent_session = agent_session
      @deployment = deployment
      @executor_program = executor_program
      @fingerprint = fingerprint
      @protocol_version = protocol_version
      @sdk_version = sdk_version
      @executor_capability_payload = executor_capability_payload
      @executor_tool_catalog = executor_tool_catalog
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

      if @executor_program.present? && (!@executor_capability_payload.nil? || !@executor_tool_catalog.nil?)
        ExecutorPrograms::RecordCapabilities.call(
          executor_program: @executor_program,
          capability_payload: @executor_capability_payload || @executor_program.capability_payload,
          tool_catalog: @executor_tool_catalog || @executor_program.tool_catalog
        )
      end

      runtime_capability_contract = RuntimeCapabilityContract.build(
        executor_program: @executor_program || @deployment.agent_program.default_executor_program,
        agent_program_version: @deployment
      )

      ToolBindings::ProjectCapabilitySnapshot.call(
        agent_program_version: @deployment,
        executor_program: @executor_program || @deployment.agent_program.default_executor_program
      )

      Result.new(
        deployment: @deployment,
        reconciliation_report: {},
        runtime_capability_contract: runtime_capability_contract
      )
    end
  end
end
