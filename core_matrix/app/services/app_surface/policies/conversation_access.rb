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
        ResourceVisibility::Usability.conversation_accessible_by_user?(
          user: @user,
          conversation: @conversation
        )
      end
    end
  end
end
