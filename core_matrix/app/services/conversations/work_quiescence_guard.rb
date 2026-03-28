module Conversations
  module WorkQuiescenceGuard
    private

    def ensure_mainline_stop_barrier_clear!(conversation, stage:)
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: stage,
        mainline_only: true
      )
    end

    def ensure_conversation_quiescent!(conversation, stage:)
      Conversations::ValidateQuiescence.call(
        conversation: conversation,
        stage: stage,
        mainline_only: false
      )
    end
  end
end
