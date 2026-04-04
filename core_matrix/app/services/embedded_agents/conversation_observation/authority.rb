module EmbeddedAgents
  module ConversationObservation
    class Authority
      PUBLIC_ID_PATTERN = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

      attr_reader :actor, :conversation, :allowed

      def self.call(...)
        new(...).call
      end

      def initialize(actor:, conversation: nil, conversation_id: nil, conversation_public_id: nil)
        @actor = actor
        @conversation = conversation
        @conversation_id = conversation_id
        @conversation_public_id = conversation_public_id
      end

      def call
        @conversation = resolve_conversation
        @allowed = owner_on_own_conversation?
        self
      end

      def allowed?
        !!@allowed
      end

      private

      def resolve_conversation
        return @conversation if @conversation.present?
        return find_by_public_id(@conversation_public_id) if @conversation_public_id.present?

        if @conversation_id.present?
          raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" if @conversation_id.is_a?(Integer)

          return find_by_public_id(@conversation_id)
        end

        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids"
      end

      def find_by_public_id(public_id)
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" unless public_id.is_a?(String)
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids" unless public_id.match?(PUBLIC_ID_PATTERN)

        Conversation.find_by_public_id!(public_id)
      rescue ActiveRecord::RecordNotFound
        raise EmbeddedAgents::Errors::InvalidTargetIdentifier, "conversation_id must use public ids"
      end

      def owner_on_own_conversation?
        return false if actor.blank? || conversation.blank?
        return false unless actor.respond_to?(:id)
        return false unless conversation.respond_to?(:workspace) && conversation.workspace.present?

        actor.id == conversation.workspace.user_id
      end
    end
  end
end
