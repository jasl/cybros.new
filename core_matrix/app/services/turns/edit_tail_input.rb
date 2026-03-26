module Turns
  class EditTailInput
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, content:)
      @turn = turn
      @content = content
    end

    def call
      Turns::WithTimelineMutationLock.call(
        turn: @turn,
        retained_message: "must be retained before editing tail input",
        active_message: "must belong to an active conversation to edit tail input",
        closing_message: "must not edit tail input while close is in progress",
        interrupted_message: "must not edit tail input after turn interruption"
      ) do |turn|
        raise_invalid!(turn, :base, "must target the selected tail input") unless turn.tail_in_active_timeline?
        raise_invalid!(turn, :selected_input_message, "must exist") if turn.selected_input_message.blank?
        raise_invalid!(turn, :base, "cannot rewrite a fork-point input") if turn.selected_input_message.fork_point?

        message = UserMessage.create!(
          installation: turn.installation,
          conversation: turn.conversation,
          turn: turn,
          role: "user",
          slot: "input",
          variant_index: turn.messages.where(slot: "input").maximum(:variant_index).to_i + 1,
          content: @content
        )

        turn.update!(
          selected_input_message: message,
          selected_output_message: nil
        )
        turn
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
