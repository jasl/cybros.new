module Publications
  class LiveProjectionQuery
    Entry = Struct.new(:entry_type, :record, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(publication:)
      @publication = publication
    end

    def call
      raise ActiveRecord::RecordNotFound, "publication is not active" unless @publication.active?

      live_entries
    end

    private

    def live_entries
      entries = []
      consumed_turn_ids = {}

      transcript_messages.each do |message|
        entries << Entry.new(entry_type: "message", record: message)

        next unless message.input?
        next unless anchored_events.key?(message.turn_id)

        anchored_events.fetch(message.turn_id).each do |event|
          entries << Entry.new(entry_type: "conversation_event", record: event)
        end
        consumed_turn_ids[message.turn_id] = true
      end

      remaining_anchored_events(consumed_turn_ids).each do |event|
        entries << Entry.new(entry_type: "conversation_event", record: event)
      end
      unanchored_events.each do |event|
        entries << Entry.new(entry_type: "conversation_event", record: event)
      end

      entries
    end

    def transcript_messages
      @publication.conversation.transcript_projection_messages
    end

    def live_events
      @live_events ||= ConversationEvent.live_projection(conversation: @publication.conversation)
    end

    def anchored_events
      @anchored_events ||= live_events.select(&:turn_id).group_by(&:turn_id)
    end

    def unanchored_events
      @unanchored_events ||= live_events.select { |event| event.turn_id.blank? }
    end

    def remaining_anchored_events(consumed_turn_ids)
      live_events
        .select { |event| event.turn_id.present? && !consumed_turn_ids[event.turn_id] }
        .sort_by { |event| [event.turn&.sequence.to_i, event.projection_sequence] }
    end
  end
end
