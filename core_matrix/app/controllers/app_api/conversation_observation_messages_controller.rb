module AppAPI
  class ConversationObservationMessagesController < BaseController
    def index
      session = find_observation_session!(params.fetch(:conversation_observation_session_id))

      render json: {
        method_id: "conversation_observation_message_list",
        conversation_id: session.target_conversation.public_id,
        observation_session_id: session.public_id,
        items: session.conversation_observation_messages.order(:created_at).map { |message| serialize_observation_message(message) },
      }
    end

    def create
      session = find_observation_session!(params.fetch(:conversation_observation_session_id))
      result = EmbeddedAgents::ConversationObservation::AppendMessage.call(
        actor: session.initiator,
        conversation_observation_session: session,
        content: params.fetch(:content)
      )

      render json: {
        method_id: "conversation_observation_message_create",
        conversation_id: session.target_conversation.public_id,
        observation_session_id: session.public_id,
        assessment: result.fetch("assessment"),
        supervisor_status: result.fetch("supervisor_status"),
        human_sidechat: result.fetch("human_sidechat"),
        user_message: serialize_observation_message(result.fetch("user_message")),
        observer_message: serialize_observation_message(result.fetch("observer_message")),
      }, status: :created
    end

    private

    def find_observation_session!(session_id)
      ConversationObservationSession.find_by!(
        public_id: session_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_observation_message(message)
      {
        "observation_message_id" => message.public_id,
        "observation_session_id" => message.conversation_observation_session.public_id,
        "observation_frame_id" => message.conversation_observation_frame.public_id,
        "target_conversation_id" => message.target_conversation.public_id,
        "role" => message.role,
        "content" => message.content,
        "metadata" => message.metadata,
        "created_at" => message.created_at&.iso8601(6),
      }
    end
  end
end
