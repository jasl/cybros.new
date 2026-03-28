module Conversations
  class ValidateArchiveTarget
    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      record: nil,
      retained_message: "must be retained before archival",
      active_attribute: :lifecycle_state,
      active_message: "must be active before archival"
    )
      @conversation = conversation
      @record = record || conversation
      @retained_message = retained_message
      @active_attribute = active_attribute
      @active_message = active_message
    end

    def call
      current_conversation = Conversations::ValidateRetainedState.call(
        conversation: @conversation,
        record: @record,
        message: @retained_message
      )

      return current_conversation if current_conversation.active?

      @record.errors.add(@active_attribute, @active_message)
      raise ActiveRecord::RecordInvalid, @record
    end
  end
end
