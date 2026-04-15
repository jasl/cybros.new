module IngressAPI
  module Preprocessors
    class ResolveDispatchDecision
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("resolve_dispatch_decision")
        active_turn = @context.active_turn || @context.conversation&.latest_active_turn
        @context.active_turn ||= active_turn

        @context.dispatch_decision =
          if active_turn.present?
            steerable_turn?(active_turn) ? "steer_current_turn" : "queue_follow_up"
          elsif queued_work_exists?
            "queue_follow_up"
          else
            "new_turn"
          end
        @context.origin_payload = {
          "platform" => @context.envelope.platform,
          "driver" => @context.envelope.driver,
          "ingress_binding_id" => @context.ingress_binding.public_id,
          "channel_connector_id" => @context.channel_connector.public_id,
          "channel_session_id" => @context.channel_session.public_id,
          "external_message_key" => @context.envelope.external_message_key,
          "external_sender_id" => @context.envelope.external_sender_id,
          "peer_kind" => @context.envelope.peer_kind,
          "peer_id" => @context.envelope.peer_id,
          "thread_key" => @context.envelope.thread_key,
          "reply_to_external_message_key" => @context.envelope.reply_to_external_message_key,
          "quoted_external_message_key" => @context.envelope.quoted_external_message_key,
          "quoted_text" => @context.envelope.quoted_text,
          "quoted_sender_label" => @context.envelope.quoted_sender_label,
          "quoted_attachment_refs" => Array(@context.envelope.quoted_attachment_refs).map do |attachment|
            attachment.respond_to?(:deep_stringify_keys) ? attachment.deep_stringify_keys : attachment
          end,
          "merged_inbound_message_ids" => Array(@context.coalesced_message_ids).presence || [],
        }
        @context
      end

      private

      def queued_work_exists?
        return false if @context.conversation.blank?

        @context.conversation.turns.where(lifecycle_state: %w[queued active]).exists?
      end

      def steerable_turn?(turn)
        sender_id = turn.origin_payload["external_sender_id"].to_s
        return false if sender_id.blank?
        return false if sender_id != @context.envelope.external_sender_id.to_s
        return false if Turns::TranscriptSideEffectBoundary.crossed?(turn)

        true
      end
    end
  end
end
