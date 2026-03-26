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
      @execution_environment.update!(
        capability_payload: @capability_payload,
        tool_catalog: @tool_catalog
      )
      @execution_environment
    end
  end
end
