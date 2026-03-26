module Conversations
  class WithMutableStateLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
    end

    def initialize(
      conversation:,
      record: nil,
      retained_attribute: :deletion_state,
      retained_message:,
      active_attribute: :lifecycle_state,
      active_message:,
      closing_attribute: :base,
      closing_message:
    )
      @conversation = conversation
      @record = record
      @retained_attribute = retained_attribute
      @retained_message = retained_message
      @active_attribute = active_attribute
      @active_message = active_message
      @closing_attribute = closing_attribute
      @closing_message = closing_message
    end

    def call
      @conversation.with_lock do
        current_conversation = Conversations::ValidateMutableState.call(
          conversation: @conversation,
          record: @record,
          retained_attribute: @retained_attribute,
          retained_message: @retained_message,
          active_attribute: @active_attribute,
          active_message: @active_message,
          closing_attribute: @closing_attribute,
          closing_message: @closing_message
        )
        yield current_conversation
      end
    end
  end
end
