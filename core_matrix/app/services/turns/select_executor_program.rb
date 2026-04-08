module Turns
  class SelectExecutorProgram
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, executor_program: nil)
      @conversation = conversation
      @requested_executor_program = executor_program
    end

    def call
      runtime = @requested_executor_program || previous_turn_runtime || @conversation.agent_program.default_executor_program
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
