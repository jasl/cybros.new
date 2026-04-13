module Turns
  class SelectExecutionRuntime
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, execution_runtime: nil)
      @conversation = conversation
      @requested_execution_runtime = execution_runtime
    end

    def call
      runtime = @requested_execution_runtime ||
        @conversation.current_execution_runtime ||
        @conversation.workspace.default_execution_runtime ||
        @conversation.agent.default_execution_runtime
      return nil if runtime.blank?
      return runtime if ExecutionRuntimeConnection.exists?(execution_runtime_id: runtime.id, lifecycle_state: "active")

      @conversation.errors.add(:base, "must have an active execution runtime connection for the selected execution runtime")
      raise ActiveRecord::RecordInvalid, @conversation
    end
  end
end
