module Conversations
  class WithChildConversationEntryLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(parent:, record: nil, entry_label:)
      @parent = parent
      @record = record || parent
      @entry_label = entry_label
    end

    def call
      Conversations::WithMutableStateLock.call(
        conversation: @parent,
        record: @record,
        retained_message: "must be retained before #{@entry_label}",
        active_message: "must be active before #{@entry_label}",
        closing_message: "must not create child conversations while close is in progress"
      ) do |parent|
        yield parent
      end
    end
  end
end
