module ExecutionSessions
  class ResolveActiveSession
    def self.call(...)
      new(...).call
    end

    def initialize(execution_runtime:)
      @execution_runtime = execution_runtime
    end

    def call
      ExecutorSession.find_by(executor_program: @execution_runtime, lifecycle_state: "active")
    end
  end
end
