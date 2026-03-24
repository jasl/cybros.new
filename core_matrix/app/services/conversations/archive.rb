module Conversations
  class Archive
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      @conversation.update!(lifecycle_state: "archived")
      @conversation
    end
  end
end
