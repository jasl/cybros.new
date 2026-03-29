module Conversations
  class WorkBarrierQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      Conversations::BlockerSnapshotQuery.call(conversation: @conversation).work_barrier
    end
  end
end
