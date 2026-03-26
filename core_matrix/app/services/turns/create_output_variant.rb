module Turns
  class CreateOutputVariant
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, content:, source_input_message: turn.selected_input_message)
      @turn = turn
      @content = content
      @source_input_message = source_input_message
    end

    def call
      validate_source_input_message!

      AgentMessage.create!(
        installation: @turn.installation,
        conversation: @turn.conversation,
        turn: @turn,
        role: "agent",
        slot: "output",
        variant_index: @turn.messages.where(slot: "output").maximum(:variant_index).to_i + 1,
        content: @content,
        source_input_message: @source_input_message
      )
    end

    private

    def validate_source_input_message!
      return if @source_input_message.blank?
      return if @source_input_message.turn_id == @turn.id && @source_input_message.input?

      @turn.errors.add(:selected_input_message, "must be an input message from the same turn")
      raise ActiveRecord::RecordInvalid, @turn
    end
  end
end
