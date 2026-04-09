module EmbeddedAgents
  module ConversationSupervision
    class CloseSession
      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation_supervision_session:)
        @actor = actor
        @conversation_supervision_session = conversation_supervision_session
      end

      def call
        authority = Authority.call(actor: @actor, conversation: target_conversation)
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless authority.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless authority.allowed?

        return conversation_supervision_session if conversation_supervision_session.closed?

        conversation_supervision_session.update!(lifecycle_state: "closed")
        conversation_supervision_session
      end

      private

      attr_reader :actor, :conversation_supervision_session

      def target_conversation
        conversation_supervision_session.target_conversation
      end
    end
  end
end
