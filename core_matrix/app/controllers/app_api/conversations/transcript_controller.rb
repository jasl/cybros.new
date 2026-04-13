module AppAPI
  module Conversations
    class TranscriptController < AppAPI::Conversations::BaseController
      def show
        result = ConversationTranscripts::PageProjection.call(
          conversation: @conversation,
          cursor: params[:cursor],
          limit: params[:limit]
        )
        turn_public_ids = turn_public_id_lookup_for(result.messages)
        conversation_public_ids = conversation_public_id_lookup_for(result.messages)

        render_method_response(
          method_id: "conversation_transcript_list",
          conversation_id: @conversation.public_id,
          items: result.messages.map do |message|
            serialize_message(
              message,
              conversation_public_id: conversation_public_ids.fetch(message.conversation_id),
              turn_public_id: turn_public_ids.fetch(message.turn_id)
            )
          end,
          next_cursor: result.next_cursor,
        )
      end

      private

      def conversation_public_id_lookup_for(messages)
        lookup = { @conversation.id => @conversation.public_id }
        missing_ids = messages.map(&:conversation_id).uniq - lookup.keys
        return lookup if missing_ids.empty?

        lookup.merge(Conversation.where(id: missing_ids).pluck(:id, :public_id).to_h)
      end

      def turn_public_id_lookup_for(messages)
        lookup = messages.each_with_object({}) do |message, hash|
          hash[message.turn_id] = message.turn.public_id if message.association(:turn).loaded?
        end
        missing_ids = messages.map(&:turn_id).uniq - lookup.keys
        return lookup if missing_ids.empty?

        lookup.merge(Turn.where(id: missing_ids).pluck(:id, :public_id).to_h)
      end
    end
  end
end
