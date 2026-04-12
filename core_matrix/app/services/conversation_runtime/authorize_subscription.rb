module ConversationRuntime
  class AuthorizeSubscription
    def self.call(...)
      new(...).call
    end

    def initialize(current_user:, conversation_id:)
      @current_user = current_user
      @conversation_id = conversation_id
    end

    def call
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" if @current_user.blank?

      conversation = Conversation.find_by_public_id!(@conversation_id)
      raise ActiveRecord::RecordNotFound, "Couldn't find Conversation" unless accessible?(conversation)

      conversation
    end

    private

    def accessible?(conversation)
      ResourceVisibility::Usability.conversation_accessible_by_user?(
        user: @current_user,
        conversation: conversation
      )
    end
  end
end
