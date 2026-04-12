module EmbeddedAgents
  module ConversationSupervision
    class CloseSession
      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:, supervision_access: nil)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
        @supervision_access = supervision_access
      end

      def call
        supervision_access = resolved_supervision_access
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless supervision_access.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless supervision_access.close_session?

        return conversation_supervision_session if conversation_supervision_session.closed?

        conversation_supervision_session.update!(lifecycle_state: "closed")
        conversation_supervision_session
      end

      private

      attr_reader :actor, :conversation_supervision_session

      def target_conversation
        conversation_supervision_session.target_conversation
      end

      def resolved_supervision_access
        @supervision_access || AppSurface::Policies::ConversationSupervisionAccess.call(
          user: actor,
          conversation_supervision_session: conversation_supervision_session
        )
      end
    end
  end
end
