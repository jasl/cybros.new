module ConversationExecutionEpochs
  class RetargetCurrent
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, execution_runtime:)
      @conversation = conversation
      @execution_runtime = execution_runtime
    end

    def call
      epoch = @conversation.current_execution_epoch ||
        ConversationExecutionEpochs::InitializeCurrent.call(
          conversation: @conversation,
          execution_runtime: @execution_runtime
        )

      epoch.update!(execution_runtime: @execution_runtime)
      @conversation.update!(
        current_execution_runtime: @execution_runtime,
        execution_continuity_state: "ready"
      )
      epoch
    end
  end
end
