module ChannelDeliveries
  class DispatchRuntimeProgress
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turn:, event_kind:, payload:)
      @conversation = conversation
      @turn = turn
      @event_kind = event_kind
      @payload = payload
    end

    def call
      IngressAPI::Telegram::ProgressBridge.call(
        conversation: @conversation,
        turn: @turn,
        event_kind: @event_kind,
        payload: @payload
      )
    end
  end
end
