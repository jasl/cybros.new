module Conversations
  class Unarchive
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      @conversation.update!(lifecycle_state: "active")
      @conversation
    end
  end
end
