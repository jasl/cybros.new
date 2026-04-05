module ConversationSupervision
  class PruneFeedWindow
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      keep_turn_ids = @conversation.turns.order(sequence: :desc).limit(2).pluck(:id)
      scope = ConversationSupervisionFeedEntry.where(target_conversation: @conversation)
      return scope.delete_all if keep_turn_ids.empty?

      scope.where.not(target_turn_id: keep_turn_ids).delete_all
    end
  end
end
