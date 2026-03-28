module Conversations
  class Unarchive
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      Conversations::WithRetainedLifecycleLock.call(
        conversation: @conversation,
        record: @conversation,
        retained_message: "must be retained before unarchival",
        expected_state: "archived",
        lifecycle_message: "must be archived before unarchival"
      ) do |conversation|
        conversation.update!(lifecycle_state: "active")
      end

      @conversation
    end
  end
end
