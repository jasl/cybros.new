module AppAPI
  module Conversations
    module Supervision
      class BaseController < AppAPI::Conversations::BaseController
        rescue_from EmbeddedAgents::Errors::UnauthorizedSupervision, with: :render_not_found

        private

        def find_supervision_session!(session_id)
          @conversation.conversation_supervision_sessions.find_by!(
            public_id: session_id,
            installation_id: current_installation_id
          )
        end

        def authorize_supervision_create!
          supervision_access = AppSurface::Policies::ConversationSupervisionAccess.call(
            user: current_user,
            conversation: @conversation
          )
          raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless supervision_access.create_session?

          supervision_access
        end

        def authorize_supervision_read!(session)
          supervision_access = AppSurface::Policies::ConversationSupervisionAccess.call(
            user: current_user,
            conversation_supervision_session: session
          )
          raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless supervision_access.read?

          supervision_access
        end

        def authorize_supervision_close!(session)
          supervision_access = authorize_supervision_read!(session)
          raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless supervision_access.close_session?

          supervision_access
        end

        def authorize_supervision_append!(session)
          supervision_access = authorize_supervision_read!(session)
          raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless supervision_access.append_message?

          supervision_access
        end

        def serialize_supervision_session(session)
          {
            "supervision_session_id" => session.public_id,
            "target_conversation_id" => @conversation.public_id,
            "initiator_type" => session.initiator_type,
            "initiator_id" => session.initiator.respond_to?(:public_id) ? session.initiator.public_id : nil,
            "lifecycle_state" => session.lifecycle_state,
            "responder_strategy" => session.responder_strategy,
            "capability_policy_snapshot" => session.capability_policy_snapshot,
            "last_snapshot_at" => session.last_snapshot_at&.iso8601(6),
            "closed_at" => session.closed_at&.iso8601(6),
            "created_at" => session.created_at&.iso8601(6),
          }.compact
        end

        def serialize_supervision_message(message)
          snapshot = message.conversation_supervision_snapshot
          raise EmbeddedAgents::Errors::UnavailableSupervisionArtifact, "supervision snapshot is unavailable" if snapshot.blank?

          {
            "supervision_message_id" => message.public_id,
            "supervision_session_id" => message.conversation_supervision_session.public_id,
            "supervision_snapshot_id" => snapshot.public_id,
            "target_conversation_id" => @conversation.public_id,
            "role" => message.role,
            "content" => message.content,
            "created_at" => message.created_at&.iso8601(6),
          }
        end
      end
    end
  end
end
