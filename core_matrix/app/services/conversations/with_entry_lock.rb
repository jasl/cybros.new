module Conversations
  class WithEntryLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(conversation:, record: nil, entry_label:, closing_action:)
      @conversation = conversation
      @record = record || conversation
      @entry_label = entry_label
      @closing_action = closing_action
    end

    def call
      Conversations::WithConversationEntryLock.call(
        conversation: @conversation,
        record: @record,
        retained_message: "must be retained before #{@entry_label}",
        active_message: "must be active before #{@entry_label}",
        closing_message: "must not #{@closing_action} while close is in progress"
      ) do |conversation|
        yield conversation
      end
    end
  end
end
