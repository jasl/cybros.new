module ExecutionEnvironments
  class RecordCapabilities
    def self.call(...)
      new(...).call
    end

    def initialize(execution_environment:, capability_payload:, tool_catalog:)
      @execution_environment = execution_environment
      @capability_payload = capability_payload
      @tool_catalog = tool_catalog
    end

    def call
      contract = RuntimeCapabilityContract.build(
        execution_environment: @execution_environment,
        environment_capability_payload: @capability_payload,
        environment_tool_catalog: @tool_catalog
      )

      @execution_environment.update!(
        capability_payload: contract.environment_capability_payload,
        tool_catalog: contract.environment_tool_catalog
      )
      @execution_environment
    end
  end
end
