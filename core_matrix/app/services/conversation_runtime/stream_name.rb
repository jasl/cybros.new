module ConversationRuntime
  class StreamName
    def self.for_conversation(conversation)
      "conversation_runtime:#{conversation.public_id}"
    end
  end
end
