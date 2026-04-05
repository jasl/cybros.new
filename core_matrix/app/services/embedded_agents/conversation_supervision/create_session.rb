module EmbeddedAgents
  module ConversationSupervision
    class CreateSession
      class UnsupportedResponderStrategy < StandardError; end

      SUPPORTED_RESPONDER_STRATEGIES = %w[builtin].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation:, responder_strategy: "builtin")
        @actor = actor
        @conversation = conversation
        @responder_strategy = normalize_responder_strategy(responder_strategy)
      end

      def call
        conversation = @conversation.reload
        authority = Authority.call(actor: @actor, conversation_id: conversation.public_id)
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless authority.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless authority.allowed?

        ConversationSupervisionSession.create!(
          installation: conversation.installation,
          target_conversation: conversation,
          initiator: @actor,
          lifecycle_state: "open",
          responder_strategy: @responder_strategy,
          capability_policy_snapshot: {
            "supervision_enabled" => authority.supervision_enabled?,
            "side_chat_enabled" => authority.side_chat_enabled?,
            "control_enabled" => authority.control_enabled?,
          }
        )
      end

      private

      def normalize_responder_strategy(responder_strategy)
        normalized = responder_strategy.presence || "builtin"
        return normalized if SUPPORTED_RESPONDER_STRATEGIES.include?(normalized)

        raise UnsupportedResponderStrategy, "unsupported supervision responder strategy #{normalized.inspect}"
      end
    end
  end
end
