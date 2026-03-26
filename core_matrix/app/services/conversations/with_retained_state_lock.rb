module Conversations
  class WithRetainedStateLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(conversation:, record: nil, attribute: :deletion_state, message:)
      @conversation = conversation
      @record = record
      @attribute = attribute
      @message = message
    end

    def call
      @conversation.with_lock do
        current_conversation = Conversations::ValidateRetainedState.call(
          conversation: @conversation,
          record: @record,
          attribute: @attribute,
          message: @message
        )
        yield current_conversation
      end
    end
  end
end
