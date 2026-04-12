module AppAPI
  class ConversationMessagesController < BaseController
    def create
      conversation = find_conversation!(params.fetch(:conversation_id))
      result = Workbench::SendMessage.call(
        conversation: conversation,
        content: params.fetch(:content)
      )

      render_method_response(
        method_id: "conversation_message_create",
        status: :created,
        conversation_id: conversation.public_id,
        turn_id: result.turn.public_id,
        message: serialize_message(result.message)
      )
    end
  end
end
