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
      return @conversation if @conversation.deleted?

      revoke_publication!
      Conversations::RequestClose.call(
        conversation: @conversation,
        intent_kind: "delete",
        occurred_at: @occurred_at
      )
    end

    private

    def revoke_publication!
      publication = @conversation.publication
      return if publication.blank? || !publication.active?

      Publications::Revoke.call(
        publication: publication,
        actor: nil,
        revoked_at: @occurred_at
      )
    end
  end
end
