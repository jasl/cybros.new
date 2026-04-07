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
      runtime = @requested_execution_runtime || previous_turn_runtime || @conversation.agent_program.default_executor_program
      return nil if runtime.blank?
      return runtime if ExecutorSession.exists?(executor_program: runtime, lifecycle_state: "active")

      @conversation.errors.add(:base, "must have an active executor session for the selected executor program")
      raise ActiveRecord::RecordInvalid, @conversation
    end

    private

    def previous_turn_runtime
      @conversation.turns.order(sequence: :desc).limit(1).pick(:executor_program_id)&.then do |runtime_id|
        ExecutorProgram.find_by(id: runtime_id)
      end
    end
  end
end
