module AppAPI
  module Conversations
    module Supervision
      class SessionsController < AppAPI::Conversations::Supervision::BaseController
        rescue_from EmbeddedAgents::ConversationSupervision::CreateSession::UnsupportedResponderStrategy,
          with: :render_unprocessable_entity
        before_action :set_supervision_session, only: [:show, :close]

        def create
          supervision_access = authorize_supervision_create!
          session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
            actor: current_user,
            conversation: @conversation,
            responder_strategy: params[:responder_strategy],
            supervision_access: supervision_access
          )

          render_method_response(
            method_id: "conversation_supervision_session_create",
            conversation_id: @conversation.public_id,
            conversation_supervision_session: serialize_supervision_session(session),
            status: :created
          )
        end

        def show
          authorize_supervision_read!(@supervision_session)
          return head :gone if @supervision_session.closed?

          render_method_response(
            method_id: "conversation_supervision_session_show",
            conversation_id: @conversation.public_id,
            conversation_supervision_session: serialize_supervision_session(@supervision_session),
          )
        end

        def close
          supervision_access = authorize_supervision_close!(@supervision_session)
          session = EmbeddedAgents::ConversationSupervision::CloseSession.call(
            actor: current_user,
            conversation_supervision_session: @supervision_session,
            supervision_access: supervision_access
          )

          render_method_response(
            method_id: "conversation_supervision_session_close",
            conversation_id: @conversation.public_id,
            conversation_supervision_session: serialize_supervision_session(session),
          )
        end

        private

        def set_supervision_session
          @supervision_session ||= find_supervision_session!(params.fetch(:id))
        end
      end
    end
  end
end
