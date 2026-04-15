module ChannelDeliveries
  class DispatchRuntimeProgress
    BRIDGES = [
      IngressAPI::Telegram::ProgressBridge,
      IngressAPI::Weixin::ProgressBridge,
    ].freeze

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
      BRIDGES.each do |bridge|
        bridge.call(
          conversation: @conversation,
          turn: @turn,
          event_kind: @event_kind,
          payload: @payload
        )
      end
    end
  end
end
