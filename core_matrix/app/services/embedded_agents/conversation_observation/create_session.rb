module EmbeddedAgents
  module ConversationObservation
    class CreateSession
      class UnsupportedResponderStrategy < StandardError; end

      SUPPORTED_RESPONDER_STRATEGIES = %w[builtin].freeze
      DEFAULT_CAPABILITY_POLICY = {
        "observe" => true,
        "control_enabled" => false,
      }.freeze

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation:, responder_strategy: "builtin", capability_policy_snapshot: DEFAULT_CAPABILITY_POLICY)
        @actor = actor
        @conversation = conversation
        @responder_strategy = normalize_responder_strategy(responder_strategy)
        @capability_policy_snapshot = capability_policy_snapshot
      end

      def call
        authority = Authority.call(actor: @actor, conversation_id: @conversation.public_id)
        raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless authority.allowed?

        ConversationObservationSession.create!(
          installation: @conversation.installation,
          target_conversation: @conversation,
          initiator: @actor,
          lifecycle_state: "open",
          responder_strategy: @responder_strategy,
          capability_policy_snapshot: @capability_policy_snapshot
        )
      end

      private

      def normalize_responder_strategy(responder_strategy)
        normalized = responder_strategy.presence || "builtin"
        return normalized if SUPPORTED_RESPONDER_STRATEGIES.include?(normalized)

        raise UnsupportedResponderStrategy, "unsupported observation responder strategy #{normalized.inspect}"
      end
    end
  end
end
