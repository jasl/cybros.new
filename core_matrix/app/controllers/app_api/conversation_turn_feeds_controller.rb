module AppAPI
  class ConversationTurnFeedsController < BaseController
    def index
      conversation = find_conversation!(params.fetch(:conversation_id))

      render json: {
        method_id: "conversation_turn_feed_list",
        conversation_id: conversation.public_id,
        items: ConversationSupervision::BuildActivityFeed.call(conversation: conversation),
      }
    end
  end
end
