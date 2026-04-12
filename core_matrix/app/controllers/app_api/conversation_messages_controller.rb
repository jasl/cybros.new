module AppAPI
  class ConversationMessagesController < BaseController
    def create
      conversation = find_conversation!(params.fetch(:conversation_id))
      result = Workbench::SendMessage.call(
        conversation: conversation,
        content: params.fetch(:content),
        selector: params[:selector],
        execution_runtime: resolve_execution_runtime
      )

      render_method_response(
        method_id: "conversation_message_create",
        status: :created,
        conversation_id: conversation.public_id,
        turn_id: result.turn.public_id,
        message: serialize_message(result.message)
      )
    end

    private

    def resolve_execution_runtime
      return nil if params[:execution_runtime_id].blank?

      find_execution_runtime!(params.fetch(:execution_runtime_id))
    end
  end
end
