module ConversationSupervision
  class BuildActivityFeed
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return [] if feed_turn.blank?

      ConversationSupervisionFeedEntry
        .where(target_conversation: @conversation, target_turn: feed_turn)
        .order(:sequence)
        .map { |entry| serialize_entry(entry) }
    end

    private

    def feed_turn
      @feed_turn ||= @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).first ||
        @conversation.turns.order(sequence: :desc).first
    end

    def serialize_entry(entry)
      {
        "conversation_id" => entry.target_conversation.public_id,
        "turn_id" => entry.target_turn&.public_id,
        "conversation_supervision_feed_entry_id" => entry.public_id,
        "sequence" => entry.sequence,
        "event_kind" => entry.event_kind,
        "summary" => entry.summary,
        "details_payload" => entry.details_payload,
        "occurred_at" => entry.occurred_at.iso8601,
      }
    end
  end
end
