module ConversationDiagnostics
  class RecomputeConversationSnapshotJob < ApplicationJob
    queue_as :maintenance

    def perform(conversation_id)
      conversation = Conversation.find_by(id: conversation_id)
      return if conversation.blank?

      ConversationDiagnostics::RecomputeConversationSnapshot.call(conversation: conversation)
    end
  end
end
