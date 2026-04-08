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
        executor_program: @executor_program,
        executor_capability_payload: @capability_payload,
        executor_tool_catalog: @tool_catalog
      )

      @executor_program.update!(
        capability_payload: contract.executor_capability_payload,
        tool_catalog: contract.executor_tool_catalog
      )
      @executor_program
    end
  end
end
