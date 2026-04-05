module AppAPI
  class ConversationObservationMessagesController < BaseController
    def index
      session = find_observation_session!(params.fetch(:conversation_observation_session_id))

      render_observation_message_list!(session)
    end

    def create
      session = find_observation_session!(params.fetch(:conversation_observation_session_id))

      result = append_observation_message!(session)
      return if performed?

      render_observation_message_create!(session, result)
    end

    private

    def find_observation_session!(session_id)
      ConversationObservationSession.find_by!(
        public_id: session_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_observation_message(message)
      session = message.conversation_observation_session
      frame = message.conversation_observation_frame
      raise ActiveRecord::RecordNotFound, "Couldn't find ConversationObservationSession" if session.blank?
      raise ActiveRecord::RecordNotFound, "Couldn't find ConversationObservationFrame" if frame.blank?

      {
        "observation_message_id" => message.public_id,
        "observation_session_id" => session.public_id,
        "observation_frame_id" => frame.public_id,
        "target_conversation_id" => message.target_conversation.public_id,
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
    rescue ActiveRecord::RecordNotFound
      head :gone
    end

    def render_observation_message_list!(session)
      conversation_id = session.target_conversation&.public_id
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if conversation_id.blank?

      render json: {
        method_id: "conversation_observation_message_list",
        conversation_id: conversation_id,
        observation_session_id: session.public_id,
        items: session.conversation_observation_messages.order(:created_at).map { |message| serialize_observation_message(message) },
      }
    rescue ActiveRecord::RecordNotFound
      head :gone
    end

    def render_observation_message_create!(session, result)
      conversation_id = session.target_conversation&.public_id
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if conversation_id.blank?

      render json: {
        method_id: "conversation_observation_message_create",
        conversation_id: conversation_id,
        observation_session_id: session.public_id,
        assessment: result.fetch("assessment"),
        supervisor_status: result.fetch("supervisor_status"),
        human_sidechat: result.fetch("human_sidechat"),
        user_message: serialize_observation_message(result.fetch("user_message")),
        observer_message: serialize_observation_message(result.fetch("observer_message")),
      }, status: :created
    rescue ActiveRecord::RecordNotFound
      head :gone
    end
  end
end
