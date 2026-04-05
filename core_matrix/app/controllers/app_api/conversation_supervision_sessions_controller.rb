module AppAPI
  class ConversationSupervisionSessionsController < BaseController
    rescue_from EmbeddedAgents::Errors::UnauthorizedSupervision, with: :render_not_found
    rescue_from EmbeddedAgents::ConversationSupervision::CreateSession::UnsupportedResponderStrategy,
      with: :render_unprocessable_entity

    def create
      conversation = find_conversation!(params.fetch(:conversation_id))
      session = EmbeddedAgents::ConversationSupervision::CreateSession.call(
        actor: conversation.workspace.user,
        conversation: conversation,
        responder_strategy: params[:responder_strategy]
      )

      render json: {
        method_id: "conversation_supervision_session_create",
        conversation_id: conversation.public_id,
        conversation_supervision_session: serialize_supervision_session(session),
      }, status: :created
    end

    def show
      session = find_supervision_session!(params.fetch(:id))
      target_conversation = session.target_conversation
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?
      return head :gone if session.closed?

      render json: {
        method_id: "conversation_supervision_session_show",
        conversation_id: target_conversation.public_id,
        conversation_supervision_session: serialize_supervision_session(session),
      }
    end

    private

    def find_supervision_session!(session_id)
      ConversationSupervisionSession.find_by!(
        public_id: session_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_supervision_session(session)
      target_conversation = session.target_conversation
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?

      {
        "supervision_session_id" => session.public_id,
        "target_conversation_id" => target_conversation.public_id,
        "initiator_type" => session.initiator_type,
        "initiator_id" => session.initiator.respond_to?(:public_id) ? session.initiator.public_id : nil,
        "lifecycle_state" => session.lifecycle_state,
        "responder_strategy" => session.responder_strategy,
        "capability_policy_snapshot" => session.capability_policy_snapshot,
        "last_snapshot_at" => session.last_snapshot_at&.iso8601(6),
        "created_at" => session.created_at&.iso8601(6),
      }.compact
    end
  end
end
