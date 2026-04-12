module AppAPI
  class ConversationTranscriptsController < BaseController
    def index
      conversation = find_conversation!(params.fetch(:conversation_id))
      result = ConversationTranscripts::PageProjection.call(
        conversation: conversation,
        cursor: params[:cursor],
        limit: params[:limit]
      )

      render_method_response(
        method_id: "conversation_transcript_list",
        conversation_id: conversation.public_id,
        items: result.messages.map { |message| serialize_message(message) },
        next_cursor: result.next_cursor,
      )
    end
  end
end
