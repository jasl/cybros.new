module ExecutionRuntimes
  class RecordCapabilities
    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime:, capability_payload:, tool_catalog:)
      @execution_runtime = execution_runtime
      @capability_payload = capability_payload
      @tool_catalog = tool_catalog
    end

    def call
      contract = RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        execution_runtime_capability_payload: @capability_payload,
        execution_runtime_tool_catalog: @tool_catalog
      )

      @execution_runtime.update!(
        capability_payload: contract.execution_runtime_capability_payload,
        tool_catalog: contract.execution_runtime_tool_catalog
      )
      @execution_runtime
    end
  end
end
