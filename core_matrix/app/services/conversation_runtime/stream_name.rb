module ConversationRuntime
  class StreamName
    def self.for_conversation(conversation)
      "conversation_runtime:#{conversation.public_id}"
    end

    def self.for_app_conversation(conversation)
      "conversation_runtime_app:#{conversation.public_id}"
    end
  end
end
