module ConversationRuntime
  class Broadcast
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, event_kind:, payload:, turn: nil, occurred_at: Time.current)
      @conversation = conversation
      @event_kind = event_kind
      @payload = payload
      @turn = turn
      @occurred_at = occurred_at
    end

    def call
      ActionCable.server.broadcast(
        ConversationRuntime::StreamName.for_conversation(@conversation),
        {
          "event_kind" => @event_kind,
          "conversation_id" => @conversation.public_id,
          "turn_id" => @turn&.public_id,
          "occurred_at" => @occurred_at.iso8601(6),
          "payload" => @payload.deep_stringify_keys,
        }.compact
      )
    end
  end
end
