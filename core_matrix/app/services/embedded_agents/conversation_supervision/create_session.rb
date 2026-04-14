module EmbeddedAgents
  module ConversationSupervision
    class CreateSession
      class UnsupportedResponderStrategy < StandardError; end

      SUPPORTED_RESPONDER_STRATEGIES = %w[hybrid summary_model builtin].freeze

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation:, responder_strategy: "hybrid", supervision_access: nil)
        @actor = actor
        @conversation = conversation
        @responder_strategy = normalize_responder_strategy(responder_strategy)
        @supervision_access = supervision_access
      end

      def call
        conversation = @conversation.reload
        supervision_access = resolved_supervision_access(conversation)
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "conversation supervision is not enabled" unless supervision_access.side_chat_enabled?
        raise EmbeddedAgents::Errors::UnauthorizedSupervision, "not allowed to supervise conversation" unless supervision_access.read?

        ConversationSupervisionSession.create!(
          installation: conversation.installation,
          target_conversation: conversation,
          user: conversation.user,
          workspace: conversation.workspace,
          agent: conversation.agent,
          initiator: @actor,
          lifecycle_state: "open",
          responder_strategy: @responder_strategy,
          capability_policy_snapshot: {
            "supervision_enabled" => supervision_access.supervision_enabled?,
            "detailed_progress_enabled" => supervision_access.detailed_progress_enabled?,
            "side_chat_enabled" => supervision_access.side_chat_enabled?,
            "control_enabled" => supervision_access.control_enabled?,
          }
        )
      end

      private

      def normalize_responder_strategy(responder_strategy)
        normalized = responder_strategy.presence || "hybrid"
        return normalized if SUPPORTED_RESPONDER_STRATEGIES.include?(normalized)

        raise UnsupportedResponderStrategy, "unsupported supervision responder strategy #{normalized.inspect}"
      end

      def resolved_supervision_access(conversation)
        @supervision_access || AppSurface::Policies::ConversationSupervisionAccess.call(
          user: @actor,
          conversation: conversation
        )
      end
    end
  end
end
