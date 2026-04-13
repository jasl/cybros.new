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
      @conversation.with_lock do
        epoch = @conversation.current_execution_epoch
        unless epoch.present?
          @conversation.errors.add(:current_execution_epoch, "must exist before retargeting execution continuity")
          raise ActiveRecord::RecordInvalid, @conversation
        end

        Conversation.transaction do
          @conversation.update!(
            current_execution_epoch: nil,
            execution_continuity_state: "not_started"
          )
          epoch.update!(execution_runtime: @execution_runtime)
          @conversation.update!(
            current_execution_epoch: epoch,
            current_execution_runtime: @execution_runtime,
            execution_continuity_state: "ready"
          )
        end

        epoch
      end
    end
  end
end
