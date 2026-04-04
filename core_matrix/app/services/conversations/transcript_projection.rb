module Conversations
  class TranscriptProjection
    def self.call(...)
      new(...).call
    end

    def self.base_messages_for(conversation:)
      new(conversation: conversation).base_messages
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      messages = base_messages
      overlay_lookup = visibility_overlay_lookup_for(messages)

      messages.reject { |message| hidden_in_projection?(message, overlay_lookup) }
    end

    def base_messages
      inherited_transcript_messages + selected_messages_for_own_turns
    end

    private

    def inherited_transcript_messages
      return [] if @conversation.parent_conversation.blank?
      return self.class.base_messages_for(conversation: @conversation.parent_conversation) if @conversation.fork?

      Conversations::HistoricalAnchorProjection.call(
        conversation: @conversation.parent_conversation,
        message: @conversation.historical_anchor_message
      )
    end

    def selected_messages_for_own_turns
      @conversation.turns.includes(:selected_input_message, :selected_output_message).order(:sequence).flat_map do |turn|
        [turn.selected_input_message, turn.selected_output_message].compact
      end
    end

    def hidden_in_projection?(message, overlay_lookup)
      projection_conversation_chain_ids_for(message)&.any? do |conversation_id|
        overlay_lookup.dig(message.id, conversation_id)&.hidden?
      end
    end

    def visibility_overlay_lookup_for(messages)
      return {} if messages.empty?

      ConversationMessageVisibility.where(
        conversation_id: projection_lineage_conversation_ids,
        message_id: messages.map(&:id)
      ).each_with_object(Hash.new { |hash, key| hash[key] = {} }) do |overlay, lookup|
        lookup[overlay.message_id][overlay.conversation_id] = overlay
      end
    end

    def projection_lineage_conversation_ids
      ids = []
      current = @conversation

      while current.present?
        ids << current.id
        current = current.parent_conversation
      end

      ids
    end

    def projection_conversation_chain_ids_for(message)
      chain_ids = []
      current = @conversation

      while current.present?
        chain_ids << current.id
        return chain_ids if current.id == message.conversation_id

        current = current.parent_conversation
      end

      nil
    end
  end
end
