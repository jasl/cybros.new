module Conversations
  class Unarchive
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      conversation = current_conversation

      Conversations::WithRetainedLifecycleLock.call(
        conversation: conversation,
        record: conversation,
        retained_message: "must be retained before unarchival",
        expected_state: "archived",
        lifecycle_message: "must be archived before unarchival"
      ) do |locked_conversation|
        locked_conversation.update!(lifecycle_state: "active")
      end

      conversation
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end
  end
end
