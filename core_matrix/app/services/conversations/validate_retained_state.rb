module Conversations
  class ValidateRetainedState
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, record: nil, attribute: :deletion_state, message:)
      @conversation = conversation
      @record = record
      @attribute = attribute
      @message = message
    end

    def call
      return current_conversation if current_conversation.retained?

      invalid_record.errors.add(@attribute, @message)
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
