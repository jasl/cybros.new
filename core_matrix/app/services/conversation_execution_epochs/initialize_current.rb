module ConversationExecutionEpochs
  class InitializeCurrent
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, execution_runtime: nil)
      @conversation = conversation
      @execution_runtime = execution_runtime
    end

    def call
      return @conversation.current_execution_epoch if @conversation.current_execution_epoch.present?

      runtime = @execution_runtime || @conversation.current_execution_runtime
      epoch = ConversationExecutionEpoch.create!(
        installation: @conversation.installation,
        conversation: @conversation,
        execution_runtime: runtime,
        sequence: next_sequence,
        lifecycle_state: "active",
        continuity_payload: {},
        opened_at: @conversation.created_at || Time.current
      )

      @conversation.update_columns(
        current_execution_epoch_id: epoch.id,
        current_execution_runtime_id: runtime&.id,
        execution_continuity_state: "ready"
      )
      @conversation.current_execution_epoch = epoch
      @conversation.current_execution_runtime = runtime
      epoch
    end

    private

    def next_sequence
      @conversation.execution_epochs.maximum(:sequence).to_i + 1
    end
  end
end
