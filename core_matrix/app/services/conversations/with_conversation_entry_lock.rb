module Conversations
  class WithConversationEntryLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(conversation:, record: nil, retained_message:, active_message:, lock_message: "must be mutable", closing_message:)
      @conversation = conversation
      @record = record || conversation
      @retained_message = retained_message
      @active_message = active_message
      @lock_message = lock_message
      @closing_message = closing_message
    end

    def call
      Conversations::WithMutableStateLock.call(
        conversation: @conversation,
        record: @record,
        retained_message: @retained_message,
        active_message: @active_message,
        lock_message: @lock_message,
        closing_message: @closing_message
      ) do |conversation|
        yield conversation
      end
    end
  end
end
