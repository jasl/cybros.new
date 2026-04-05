module AppAPI
  class ConversationObservationMessagesController < BaseController
    rescue_from EmbeddedAgents::Errors::UnauthorizedObservation, with: :render_not_found
    rescue_from EmbeddedAgents::Errors::ClosedObservationSession, with: :render_gone
    rescue_from EmbeddedAgents::Errors::UnavailableObservationArtifact, with: :render_gone

    def index
      session = find_observation_session!(params.fetch(:conversation_observation_session_id))
      target_conversation = session.target_conversation
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?
      return head :gone if session.closed?

      render_observation_message_list!(session, target_conversation_id: target_conversation.public_id)
    end

    def create
      session = find_observation_session!(params.fetch(:conversation_observation_session_id))
      result = append_observation_message!(session)
      render_observation_message_create!(session, result) unless performed?
    end

    private

    def find_observation_session!(session_id)
      ConversationObservationSession.find_by!(
        public_id: session_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_observation_message(message, target_conversation_id:)
      session = message.conversation_observation_session
      frame = message.conversation_observation_frame
      raise ActiveRecord::RecordNotFound, "Couldn't find ConversationObservationSession" if session.blank?
      raise EmbeddedAgents::Errors::UnavailableObservationArtifact, "observation frame is unavailable" if frame.blank?

      {
        "observation_message_id" => message.public_id,
        "observation_session_id" => session.public_id,
        "observation_frame_id" => frame.public_id,
        "target_conversation_id" => target_conversation_id,
        "role" => message.role,
        "content" => message.content,
        "created_at" => message.created_at&.iso8601(6),
      }
    end

    def append_observation_message!(session)
      EmbeddedAgents::ConversationObservation::AppendMessage.call(
        actor: session.initiator,
        conversation_observation_session: session,
        content: params.fetch(:content)
      )
    end

    def render_observation_message_list!(session, target_conversation_id:)
      render json: {
        method_id: "conversation_observation_message_list",
        conversation_id: target_conversation_id,
        observation_session_id: session.public_id,
        items: session.conversation_observation_messages.order(:created_at).map { |message| serialize_observation_message(message, target_conversation_id:) },
      }
    end

    def render_observation_message_create!(session, result)
      target_conversation_id = session.target_conversation&.public_id
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation_id.blank?

      render json: {
        method_id: "conversation_observation_message_create",
        conversation_id: target_conversation_id,
        observation_session_id: session.public_id,
        assessment: result.fetch("assessment"),
        supervisor_status: result.fetch("supervisor_status"),
        human_sidechat: result.fetch("human_sidechat"),
        user_message: serialize_observation_message(result.fetch("user_message"), target_conversation_id: target_conversation_id),
        observer_message: serialize_observation_message(result.fetch("observer_message"), target_conversation_id: target_conversation_id),
      }, status: :created
    end

    def render_gone(_error)
      head :gone
    end
  end
end
