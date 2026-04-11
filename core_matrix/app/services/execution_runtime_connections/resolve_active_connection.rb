module ExecutionRuntimeConnections
  class ResolveActiveConnection
    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime:)
      @execution_runtime = execution_runtime
    end

    def call
      ExecutionRuntimeConnection.find_by(execution_runtime: @execution_runtime, lifecycle_state: "active")
    end
  end
end
