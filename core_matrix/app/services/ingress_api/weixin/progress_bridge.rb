module IngressAPI
  module Weixin
    class ProgressBridge
      SUPPORTED_EVENT_KINDS = [
        "runtime.assistant_output.started",
      ].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(conversation:, turn:, event_kind:, payload:)
        @conversation = conversation
        @turn = turn
        @event_kind = event_kind
        @payload = payload.deep_stringify_keys
      end

      def call
        return if @turn.blank?
        return unless SUPPORTED_EVENT_KINDS.include?(@event_kind)

        weixin_sessions.each do |channel_session|
          ChannelDeliveries::DispatchConversationOutput.call(
            conversation: @conversation,
            turn: @turn,
            channel_session: channel_session,
            delivery_mode: "status_progress",
            chat_action: "typing"
          )
        end
      end

      private

      def weixin_sessions
        ChannelSession.where(
          installation_id: @conversation.installation_id,
          conversation_id: @conversation.id,
          binding_state: "active",
          platform: "weixin"
        ).order(:id)
      end
    end
  end
end
