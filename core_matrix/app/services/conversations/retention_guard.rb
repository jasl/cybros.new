module Conversations
  module RetentionGuard
    private

    def ensure_conversation_retained!(conversation, message:)
      current_conversation =
        if conversation.persisted? && !conversation.destroyed?
          conversation.class.find(conversation.id)
        else
          conversation
        end
      return if current_conversation.retained?

      current_conversation.errors.add(:deletion_state, message)
      raise ActiveRecord::RecordInvalid, current_conversation
    end
  end
end
