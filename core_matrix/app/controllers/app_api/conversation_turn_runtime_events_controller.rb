module AppAPI
  class ConversationTurnRuntimeEventsController < BaseController
    def index
      conversation = find_conversation!(params.fetch(:conversation_id))
      turn = find_turn_for_conversation!(conversation, params.fetch(:turn_id))
      stream = ConversationRuntime::BuildTurnEventStreamForTurn.call(conversation: conversation, turn: turn)

      render_method_response(
        method_id: "conversation_turn_runtime_event_list",
        conversation_id: conversation.public_id,
        turn_id: turn.public_id,
        summary: stream.fetch("summary"),
        lanes: stream.fetch("lanes"),
        segments: stream.fetch("segments"),
        items: stream.fetch("timeline"),
      )
    end

    private

    def find_turn_for_conversation!(conversation, turn_id)
      turn = find_turn!(turn_id)
      raise ActiveRecord::RecordNotFound, "Couldn't find Turn" unless turn.conversation_id == conversation.id

      turn
    end
  end
end
