module ExecutorSessions
  class ResolveActiveSession
    def self.call(...)
      new(...).call
    end

    def initialize(executor_program:)
      @executor_program = executor_program
    end

    def call
      ExecutorSession.find_by(executor_program: @executor_program, lifecycle_state: "active")
    end
  end
end
