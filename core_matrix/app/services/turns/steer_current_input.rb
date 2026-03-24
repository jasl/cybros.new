module Turns
  class SteerCurrentInput
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, content:)
      @turn = turn
      @content = content
    end

    def call
      raise_invalid!(@turn, :lifecycle_state, "must be active to steer current input") unless @turn.active?
      raise_invalid!(@turn, :selected_output_message, "must be blank before steering current input") if @turn.selected_output_message.present?

      ApplicationRecord.transaction do
        message = UserMessage.create!(
          installation: @turn.installation,
          conversation: @turn.conversation,
          turn: @turn,
          role: "user",
          slot: "input",
          variant_index: @turn.messages.where(slot: "input").maximum(:variant_index).to_i + 1,
          content: @content
        )

        @turn.update!(selected_input_message: message)
        @turn
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
