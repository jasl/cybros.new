module Conversations
  class RefreshRuntimeContract
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      validate_runtime_binding!

      RuntimeCapabilities::ComposeForConversation.call(conversation: @conversation)
    end

    private

    def validate_runtime_binding!
      return if @conversation.agent_deployment.execution_environment_id == @conversation.execution_environment_id

      @conversation.errors.add(:agent_deployment, "must belong to the bound execution environment")
      raise ActiveRecord::RecordInvalid, @conversation
    end
  end
end
