module Conversations
  class ValidateMutableState
    def self.call(...)
      new(...).call
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
      Conversations::ValidateRetainedState.call(
        conversation: current_conversation,
        record: invalid_record,
        attribute: @retained_attribute,
        message: @retained_message
      )

      unless current_conversation.active?
        invalid_record.errors.add(@active_attribute, @active_message)
        raise ActiveRecord::RecordInvalid, invalid_record
      end

      return current_conversation unless current_conversation.closing?

      invalid_record.errors.add(@closing_attribute, @closing_message)
      raise ActiveRecord::RecordInvalid, invalid_record
    end

    private

    def current_conversation
      @current_conversation ||=
        if @conversation.persisted? && !@conversation.destroyed?
          @conversation.reload
        else
          @conversation
        end
    end

    def invalid_record
      @invalid_record ||= @record || current_conversation
    end
  end
end
