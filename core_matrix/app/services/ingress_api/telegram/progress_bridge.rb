module IngressAPI
  module Telegram
    class ProgressBridge
      SUPPORTED_EVENT_PREFIXES = [
        "runtime.assistant_output."
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
        return unless SUPPORTED_EVENT_PREFIXES.any? { |prefix| @event_kind.start_with?(prefix) }

        telegram_sessions.each do |channel_session|
          case @event_kind
          when "runtime.assistant_output.started"
            dispatch_status_progress(channel_session)
          when "runtime.assistant_output.delta"
            dispatch_preview_update(channel_session)
          end
        end
      end

      private

      def telegram_sessions
        ChannelSession.where(
          installation_id: @conversation.installation_id,
          conversation_id: @conversation.id,
          binding_state: "active",
          platform: "telegram"
        ).order(:id)
      end

      def dispatch_status_progress(channel_session)
        ChannelDeliveries::DispatchConversationOutput.call(
          conversation: @conversation,
          turn: @turn,
          channel_session: channel_session,
          delivery_mode: "status_progress",
          chat_action: "typing"
        )
      end

      def dispatch_preview_update(channel_session)
        preview_text = append_preview_delta!(channel_session)
        return if preview_text.blank?

        ChannelDeliveries::DispatchConversationOutput.call(
          conversation: @conversation,
          turn: @turn,
          channel_session: channel_session,
          text: preview_text,
          delivery_mode: "preview_stream"
        )
      end

      def append_preview_delta!(channel_session)
        delta = @payload["delta"].to_s
        return if delta.blank?

        session_metadata = channel_session.session_metadata.deep_stringify_keys
        preview_text = session_metadata[ChannelDeliveries::DispatchConversationOutput::PREVIEW_BUFFER_KEY].to_s + delta
        channel_session.update!(
          session_metadata: session_metadata.merge(
            ChannelDeliveries::DispatchConversationOutput::PREVIEW_BUFFER_KEY => preview_text
          )
        )
        preview_text
      end
    end
  end
end
