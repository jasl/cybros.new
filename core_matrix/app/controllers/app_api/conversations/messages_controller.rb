module AppAPI
  module Conversations
    class MessagesController < AppAPI::Conversations::BaseController
      def create
        if params.key?(:execution_runtime_id)
          return render_method_response(
            method_id: "conversation_runtime_handoff_not_implemented",
            status: :unprocessable_entity,
            error: "conversation runtime handoff is not implemented yet"
          )
        end

        result = Workbench::SendMessage.call(
          conversation: @conversation,
          content: params.fetch(:content),
          selector: params[:selector]
        )

        render_method_response(
          method_id: "conversation_message_create",
          status: :created,
          conversation_id: @conversation.public_id,
          turn_id: result.turn.public_id,
          execution_status: result.turn.workflow_bootstrap_state,
          accepted_at: result.turn.workflow_bootstrap_requested_at&.iso8601(6),
          request_summary: ConversationSupervision::BuildGoalSummary.call(content: result.message.content),
          message: serialize_message(result.message)
        )
      end
    end
  end
end
