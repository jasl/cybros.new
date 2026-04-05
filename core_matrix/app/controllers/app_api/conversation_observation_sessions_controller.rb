module AppAPI
  class ConversationObservationSessionsController < BaseController
    rescue_from EmbeddedAgents::ConversationObservation::CreateSession::UnsupportedResponderStrategy,
      with: :render_unprocessable_entity

    def create
      conversation = find_conversation!(params.fetch(:conversation_id))
      session = EmbeddedAgents::ConversationObservation::CreateSession.call(
        actor: conversation.workspace.user,
        conversation: conversation,
        responder_strategy: params[:responder_strategy]
      )

      render_observation_session!(
        method_id: "conversation_observation_session_create",
        session: session,
        conversation_id: conversation.public_id,
        status: :created
      )
    end

    def show
      session = find_observation_session!(params.fetch(:id))

      render_observation_session!(
        method_id: "conversation_observation_session_show",
        session: session
      )
    end

    private

    def find_observation_session!(session_id)
      ConversationObservationSession.find_by!(
        public_id: session_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_observation_session(session)
      target_conversation = session.target_conversation
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?

      {
        "observation_session_id" => session.public_id,
        "target_conversation_id" => target_conversation.public_id,
        "initiator_type" => session.initiator_type,
        "initiator_id" => session.initiator.respond_to?(:public_id) ? session.initiator.public_id : nil,
        "lifecycle_state" => session.lifecycle_state,
        "responder_strategy" => session.responder_strategy,
        "capability_policy_snapshot" => session.capability_policy_snapshot,
        "last_observed_at" => session.last_observed_at&.iso8601(6),
        "created_at" => session.created_at&.iso8601(6),
      }.compact
    end

    def render_observation_session!(method_id:, session:, status: :ok, conversation_id: nil)
      conversation_id ||= session.target_conversation&.public_id
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if conversation_id.blank?

      render json: {
        method_id: method_id,
        conversation_id: conversation_id,
        conversation_observation_session: serialize_observation_session(session),
      }, status: status
    rescue ActiveRecord::RecordNotFound
      head :gone
    end
  end
end
