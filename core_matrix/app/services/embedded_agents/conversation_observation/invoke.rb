module EmbeddedAgents
  module ConversationObservation
    class Invoke
      def self.call(...)
        new(...).call
      end

      def initialize(actor:, target:, input:, options: {}, agent_key: "conversation_observation")
        @actor = actor
        @target = target
        @input = input
        @options = options
        @agent_key = agent_key
      end

      def call
        authority = Authority.call(actor: @actor, conversation_id: conversation_id_from_target)
        raise EmbeddedAgents::Errors::UnauthorizedObservation, "not allowed to observe conversation" unless authority.allowed?

        EmbeddedAgents::Result.new(
          agent_key: @agent_key,
          status: "ok",
          output: {
            "conversation_id" => authority.conversation.public_id,
            "conversation_observation_allowed" => true,
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
