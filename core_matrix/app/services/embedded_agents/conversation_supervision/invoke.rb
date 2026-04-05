module EmbeddedAgents
  module ConversationSupervision
    class Invoke
      def self.call(...)
        new(...).call
      end

      def initialize(actor:, target:, input:, options: {}, agent_key: "conversation_supervision")
        @actor = actor
        @target = target
        @input = input
        @options = options
        @agent_key = agent_key
      end

      def call
        authority = Authority.call(actor: @actor, conversation_id: conversation_id_from_target)
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless authority.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless authority.allowed?

        EmbeddedAgents::Result.new(
          agent_key: @agent_key,
          status: "ok",
          output: {
            "conversation_id" => authority.conversation.public_id,
            "conversation_supervision_allowed" => true,
          },
          metadata: {
            "mode" => "builtin",
          },
          responder_kind: "builtin"
        )
      end

      private

      def conversation_id_from_target
        conversation_id = @target.fetch("conversation_id", @target[:conversation_id])

        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "target must use public ids" if conversation_id.is_a?(Integer)
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" unless conversation_id.is_a?(String)

        conversation_id
      end
    end
  end
end
