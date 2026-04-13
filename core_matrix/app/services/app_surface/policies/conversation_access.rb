module AppSurface
  module Policies
    class ConversationAccess
      def self.call(...)
        new(...).call
      end

      def initialize(user:, conversation:)
        @user = user
        @conversation = conversation
      end

      def call
        return false if @user.blank? || @conversation.blank?

        Conversation.accessible_to_user(@user).where(id: @conversation.id).exists?
      end
    end
  end
end
