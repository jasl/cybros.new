module Conversations
  class WorkBarrierQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turns: conversation.turns)
      @conversation = conversation
      @turns = turns
    end

    def call
      Conversations::BlockerSnapshotQuery.call(
        conversation: @conversation,
        turns: @turns
      ).work_barrier
    end
  end
end
