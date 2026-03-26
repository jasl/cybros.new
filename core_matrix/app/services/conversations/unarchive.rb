module Conversations
  class Unarchive
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      ApplicationRecord.transaction do
        @conversation.with_lock do
          Conversations::ValidateRetainedState.call(
            conversation: @conversation,
            record: @conversation,
            message: "must be retained before unarchival"
          )
          raise_invalid!(@conversation, :lifecycle_state, "must be archived before unarchival") unless @conversation.archived?
          @conversation.update!(lifecycle_state: "active")
        end
      end

      @conversation
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
