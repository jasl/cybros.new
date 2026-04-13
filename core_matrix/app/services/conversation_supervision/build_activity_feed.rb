module ConversationSupervision
  class BuildActivityFeed
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return [] if feed_turn_id.blank?

      entries = ConversationSupervisionFeedEntry
        .left_outer_joins(:target_turn)
        .select("conversation_supervision_feed_entries.*", "turns.public_id AS target_turn_public_id")
        .where(target_conversation: @conversation, target_turn_id: feed_turn_id)
        .order(:sequence)
        .to_a

      entries.map { |entry| serialize_entry(entry) }
    end

    private

    def feed_turn_id
      @feed_turn_id ||= @conversation.latest_active_turn_id ||
        @conversation.latest_turn_id ||
        @conversation.turns.where(lifecycle_state: "active").order(sequence: :desc).limit(1).pick(:id) ||
        @conversation.turns.order(sequence: :desc).limit(1).pick(:id)
    end

    def serialize_entry(entry)
      {
        "conversation_id" => @conversation.public_id,
        "turn_id" => entry.target_turn_id.present? ? entry.read_attribute("target_turn_public_id") : nil,
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
