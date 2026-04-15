module IngressAPI
  module Preprocessors
    class CoalesceBurst
      def self.call(...)
        new(...).call
      end

      def initialize(context:)
        @context = context
      end

      def call
        @context.append_trace("coalesce_burst")
        @context.coalesced_message_ids ||= []
        return @context if @context.active_turn.blank?
        return @context unless same_sender_as_active_turn?
        return @context if Turns::TranscriptSideEffectBoundary.crossed?(@context.active_turn)

        prior_text = @context.active_turn.selected_input_message&.content.to_s
        current_text = @context.envelope.text.to_s
        return @context if prior_text.blank? || current_text.blank?

        merged_text = [prior_text, current_text].join("\n")
        @context.coalesced_message_ids = (
          prior_merged_inbound_ids +
          Array(@context.coalesced_message_ids)
        ).uniq
        @context.envelope = clone_envelope(text: merged_text)
        @context
      end

      private

      def same_sender_as_active_turn?
        @context.active_turn.origin_payload["external_sender_id"].to_s ==
          @context.envelope.external_sender_id.to_s
      end

      def prior_merged_inbound_ids
        ids = Array(@context.active_turn.origin_payload["merged_inbound_message_ids"]).compact
        return ids if ids.present?

        [@context.active_turn.source_ref_id].compact
      end

      def clone_envelope(text:)
        attributes = IngressAPI::Envelope::ATTRIBUTES.index_with do |attribute|
          @context.envelope.public_send(attribute)
        end

        IngressAPI::Envelope.new(**attributes.merge(text: text))
      end
    end
  end
end
