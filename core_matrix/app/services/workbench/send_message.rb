module Workbench
  class SendMessage
    Result = Struct.new(:conversation, :turn, :message, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:)
      @conversation = conversation
      @content = content
    end

    def call
      turn = Turns::StartUserTurn.call(
        conversation: @conversation,
        content: @content,
        resolved_config_snapshot: {},
        resolved_model_selection_snapshot: {}
      )

      Result.new(
        conversation: @conversation,
        turn: turn,
        message: turn.selected_input_message
      )
    end
  end
end
