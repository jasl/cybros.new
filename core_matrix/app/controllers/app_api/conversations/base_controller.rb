module AppAPI
  module Conversations
    class BaseController < AppAPI::BaseController
      before_action :set_conversation

      private

      def set_conversation
        @conversation ||= find_conversation!(params.fetch(:conversation_id))
      end
    end
  end
end
