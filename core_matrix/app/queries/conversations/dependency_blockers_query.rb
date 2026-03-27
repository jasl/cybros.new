module Conversations
  class DependencyBlockersQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      Conversations::BlockerSnapshotQuery.call(conversation: @conversation).dependency_blockers
    end
  end
end
