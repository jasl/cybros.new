module ConversationEvents
  class Project
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, event_kind:, payload:, turn: nil, source: nil, stream_key: nil)
      @conversation = conversation
      @event_kind = event_kind
      @payload = payload
      @turn = turn
      @source = source
      @stream_key = stream_key
    end

    def call
      ConversationEvent.create!(
        installation: @conversation.installation,
        conversation: @conversation,
        turn: @turn,
        source: @source,
        projection_sequence: next_projection_sequence,
        event_kind: @event_kind,
        stream_key: @stream_key,
        stream_revision: next_stream_revision,
        payload: @payload
      )
    end

    private

    def next_projection_sequence
      current_maximum = ConversationEvent.where(conversation: @conversation).maximum(:projection_sequence)
      current_maximum.nil? ? 0 : current_maximum + 1
    end

    def next_stream_revision
      return if @stream_key.blank?

      current_maximum = ConversationEvent.where(conversation: @conversation, stream_key: @stream_key).maximum(:stream_revision)
      current_maximum.nil? ? 0 : current_maximum + 1
    end
  end
end
