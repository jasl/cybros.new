module AppAPI
  module Conversations
    class TranscriptController < AppAPI::Conversations::BaseController
      def show
        result = ConversationTranscripts::PageProjection.call(
          conversation: @conversation,
          cursor: params[:cursor],
          limit: params[:limit]
        )

        render_method_response(
          method_id: "conversation_transcript_list",
          conversation_id: @conversation.public_id,
          items: result.messages.map { |message| serialize_message(message) },
          next_cursor: result.next_cursor,
        )
      end
    end
  end
end
