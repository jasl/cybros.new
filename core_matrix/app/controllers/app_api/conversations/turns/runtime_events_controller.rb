module AppAPI
  module Conversations
    module Turns
      class RuntimeEventsController < AppAPI::Conversations::Turns::BaseController
        def index
          stream = ConversationRuntime::BuildTurnEventStreamForTurn.call(conversation: @conversation, turn: @turn)

          render_method_response(
            method_id: "conversation_turn_runtime_event_list",
            conversation_id: @conversation.public_id,
            turn_id: @turn.public_id,
            summary: stream.fetch("summary"),
            lanes: stream.fetch("lanes"),
            segments: stream.fetch("segments"),
            items: stream.fetch("timeline"),
          )
        end
      end
    end
  end
end
