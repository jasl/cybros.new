module Conversations
  class ContextProjection
    Result = Struct.new(:messages, :attachments, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      messages = Conversations::TranscriptProjection.base_messages_for(conversation: @conversation)
      overlay_lookup = visibility_overlay_lookup_for(messages)
      projected_messages = messages.reject do |message|
        hidden_in_projection?(message, overlay_lookup) ||
          excluded_from_context_in_projection?(message, overlay_lookup)
      end

      Result.new(
        messages: projected_messages,
        attachments: projected_messages.flat_map { |message| message.message_attachments.order(:id).to_a }
      )
    end

    private

    def hidden_in_projection?(message, overlay_lookup)
      projection_conversation_chain_ids_for(message)&.any? do |conversation_id|
        overlay_lookup.dig(message.id, conversation_id)&.hidden?
      end
    end

    def excluded_from_context_in_projection?(message, overlay_lookup)
      projection_conversation_chain_ids_for(message)&.any? do |conversation_id|
        overlay_lookup.dig(message.id, conversation_id)&.excluded_from_context?
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
