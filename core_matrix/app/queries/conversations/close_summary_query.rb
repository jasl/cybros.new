module Conversations
  class CloseSummaryQuery
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      Conversations::BlockerSnapshotQuery.call(conversation: @conversation).close_summary
    end
  end
end
