module Turns
  class ValidateConversationTurnEntry
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, entry_label:, record: nil, closing_message: "must not accept new turn entry while close is in progress")
      @conversation = conversation
      @entry_label = entry_label
      @record = record || conversation
      @closing_message = closing_message
    end

    def call
      Conversations::ValidateMutableState.call(
        conversation: @conversation,
        record: @record,
        retained_message: "must be retained for #{@entry_label}",
        active_message: "must be active for #{@entry_label}",
        closing_message: @closing_message
      )
    end
  end
end
