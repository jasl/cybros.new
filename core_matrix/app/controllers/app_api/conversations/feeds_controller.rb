module AppAPI
  module Conversations
    class FeedsController < AppAPI::Conversations::BaseController
      def show
        ::Conversations::UpdateSupervisionState.call(conversation: @conversation, occurred_at: Time.current)

        render_method_response(
          method_id: "conversation_turn_feed_list",
          conversation_id: @conversation.public_id,
          items: ConversationSupervision::BuildActivityFeed.call(conversation: @conversation),
        )
      end
    end
  end
end
