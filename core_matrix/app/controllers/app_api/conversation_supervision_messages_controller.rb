module AppAPI
  class ConversationSupervisionMessagesController < BaseController
    rescue_from EmbeddedAgents::Errors::UnauthorizedSupervision, with: :render_not_found
    rescue_from EmbeddedAgents::Errors::ClosedSupervisionSession, with: :render_gone
    rescue_from EmbeddedAgents::Errors::UnavailableSupervisionArtifact, with: :render_gone

    def index
      session = find_supervision_session!(params.fetch(:conversation_supervision_session_id))
      target_conversation = session.target_conversation
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation.blank?
      return head :gone if session.closed?

      render_supervision_message_list!(session, target_conversation_id: target_conversation.public_id)
    end

    def create
      session = find_supervision_session!(params.fetch(:conversation_supervision_session_id))
      result = append_supervision_message!(session)
      render_supervision_message_create!(session, result) unless performed?
    end

    private

    def find_supervision_session!(session_id)
      ConversationSupervisionSession.find_by!(
        public_id: session_id,
        installation_id: current_installation_id
      )
    end

    def serialize_supervision_message(message, target_conversation_id:)
      session = message.conversation_supervision_session
      snapshot = message.conversation_supervision_snapshot
      raise ActiveRecord::RecordNotFound, "Couldn't find ConversationSupervisionSession" if session.blank?
      raise EmbeddedAgents::Errors::UnavailableSupervisionArtifact, "supervision snapshot is unavailable" if snapshot.blank?

      {
        "supervision_message_id" => message.public_id,
        "supervision_session_id" => session.public_id,
        "supervision_snapshot_id" => snapshot.public_id,
        "target_conversation_id" => target_conversation_id,
        "role" => message.role,
        "content" => message.content,
        "created_at" => message.created_at&.iso8601(6),
      }
    end

    def append_supervision_message!(session)
      EmbeddedAgents::ConversationSupervision::AppendMessage.call(
        actor: current_user,
        conversation_supervision_session: session,
        content: params.fetch(:content)
      )
    end

    def render_supervision_message_list!(session, target_conversation_id:)
      render_method_response(
        method_id: "conversation_supervision_message_list",
        conversation_id: target_conversation_id,
        supervision_session_id: session.public_id,
        items: session.conversation_supervision_messages.order(:created_at).map { |message| serialize_supervision_message(message, target_conversation_id:) },
      )
    end

    def render_supervision_message_create!(session, result)
      target_conversation_id = session.target_conversation&.public_id
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if target_conversation_id.blank?

      render_method_response(
        method_id: "conversation_supervision_message_create",
        conversation_id: target_conversation_id,
        supervision_session_id: session.public_id,
        machine_status: result.fetch("machine_status"),
        human_sidechat: result.fetch("human_sidechat"),
        user_message: serialize_supervision_message(result.fetch("user_message"), target_conversation_id: target_conversation_id),
        supervisor_message: serialize_supervision_message(result.fetch("supervisor_message"), target_conversation_id: target_conversation_id),
        status: :created
      )
    end

    def render_gone(_error)
      head :gone
    end
  end
end
