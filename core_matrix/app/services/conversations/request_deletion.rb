module Conversations
  class RequestDeletion
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current)
      @conversation = conversation
      @occurred_at = occurred_at
    end

    def call
      conversation = current_conversation
      return conversation if conversation.deleted?

      revoke_publication!(conversation)
      Conversations::RequestClose.call(
        conversation: conversation,
        intent_kind: "delete",
        occurred_at: @occurred_at
      )
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end

    def revoke_publication!(conversation)
      publication = conversation.publication
      return if publication.blank? || !publication.active?

      Publications::Revoke.call(
        publication: publication,
        actor: nil,
        revoked_at: @occurred_at
      )
    end
  end
end
