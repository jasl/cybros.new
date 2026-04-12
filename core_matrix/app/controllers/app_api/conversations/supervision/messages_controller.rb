module AppAPI
  module Conversations
    module Supervision
      class MessagesController < AppAPI::Conversations::Supervision::BaseController
        rescue_from EmbeddedAgents::Errors::ClosedSupervisionSession, with: :render_gone
        rescue_from EmbeddedAgents::Errors::UnavailableSupervisionArtifact, with: :render_gone
        before_action :set_supervision_session

        def index
          authorize_supervision_read!(@supervision_session)
          return head :gone if @supervision_session.closed?

          render_method_response(
            method_id: "conversation_supervision_message_list",
            conversation_id: @conversation.public_id,
            supervision_session_id: @supervision_session.public_id,
            items: @supervision_session.conversation_supervision_messages.order(:created_at).map { |message| serialize_supervision_message(message) },
          )
        end

        def create
          supervision_access = authorize_supervision_append!(@supervision_session)
          result = EmbeddedAgents::ConversationSupervision::AppendMessage.call(
            actor: current_user,
            conversation_supervision_session: @supervision_session,
            content: params.fetch(:content),
            supervision_access: supervision_access
          )

          render_method_response(
            method_id: "conversation_supervision_message_create",
            conversation_id: @conversation.public_id,
            supervision_session_id: @supervision_session.public_id,
            machine_status: result.fetch("machine_status"),
            human_sidechat: result.fetch("human_sidechat"),
            user_message: serialize_supervision_message(result.fetch("user_message")),
            supervisor_message: serialize_supervision_message(result.fetch("supervisor_message")),
            status: :created
          )
        end

        private

        def set_supervision_session
          @supervision_session ||= find_supervision_session!(params.fetch(:supervision_session_id))
        end

        def render_gone(_error)
          head :gone
        end
      end
    end
  end
end
