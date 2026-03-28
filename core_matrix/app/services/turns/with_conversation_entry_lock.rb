module Turns
  class WithConversationEntryLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(conversation:, entry_label:, record: nil, closing_message: "must not accept new turn entry while close is in progress")
      @conversation = conversation
      @entry_label = entry_label
      @record = record || conversation
      @closing_message = closing_message
    end

    def call
      @conversation.with_lock do
        current_conversation = Conversations::ValidateMutableState.call(
          conversation: @conversation,
          record: @record,
          retained_message: "must be retained for #{@entry_label}",
          active_message: "must be active for #{@entry_label}",
          closing_message: @closing_message
        )
        yield current_conversation
      end
    end
  end
end
