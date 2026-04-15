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
      lock_attribute: :interaction_lock_state,
      lock_message: "must be mutable",
      closing_attribute: :base,
      closing_message:
    )
      @conversation = conversation
      @record = record
      @retained_attribute = retained_attribute
      @retained_message = retained_message
      @active_attribute = active_attribute
      @active_message = active_message
      @lock_attribute = lock_attribute
      @lock_message = lock_message
      @closing_attribute = closing_attribute
      @closing_message = closing_message
    end

    def call
      case live_mutation_block_reason
      when :retained
        Conversations::ValidateRetainedState.call(
          conversation: current_conversation,
          record: invalid_record,
          attribute: @retained_attribute,
          message: @retained_message
        )
      when :inactive
        invalid_record.errors.add(@active_attribute, @active_message)
        raise ActiveRecord::RecordInvalid, invalid_record
      when :locked
        invalid_record.errors.add(@lock_attribute, @lock_message)
        raise ActiveRecord::RecordInvalid, invalid_record
      when :closing
        invalid_record.errors.add(@closing_attribute, @closing_message)
        raise ActiveRecord::RecordInvalid, invalid_record
      end

      current_conversation
    end

    private

    def current_conversation
      @current_conversation ||= @conversation
    end

    def invalid_record
      @invalid_record ||= @record || current_conversation
    end

    def live_mutation_block_reason
      return :retained unless current_conversation.retained?
      return :inactive unless current_conversation.active?
      return :locked unless current_conversation.interaction_lock_mutable?

      :closing if current_conversation.closing?
    end
  end
end
