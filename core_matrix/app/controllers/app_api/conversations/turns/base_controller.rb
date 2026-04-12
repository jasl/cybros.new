module AppAPI
  module Conversations
    module Turns
      class BaseController < AppAPI::Conversations::BaseController
        before_action :set_turn

        private

        def set_turn
          @turn ||= find_turn!(params.fetch(:turn_id))
          raise ActiveRecord::RecordNotFound, "Couldn't find Turn" unless @turn.conversation_id == @conversation.id
        end
      end
    end
  end
end
