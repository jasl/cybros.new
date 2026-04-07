module ExecutorPrograms
  class RecordCapabilities
    def self.call(...)
      new(...).call
    end

    def initialize(executor_program:, capability_payload:, tool_catalog:)
      @executor_program = executor_program
      @capability_payload = capability_payload
      @tool_catalog = tool_catalog
    end

    def call
      contract = RuntimeCapabilityContract.build(
        execution_runtime: @executor_program,
        execution_capability_payload: @capability_payload,
        execution_tool_catalog: @tool_catalog
      )

      @executor_program.update!(
        capability_payload: contract.execution_capability_payload,
        tool_catalog: contract.execution_tool_catalog
      )
      @executor_program
    end
  end
end
