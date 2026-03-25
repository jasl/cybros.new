module Turns
  class RetryOutput
    def self.call(...)
      new(...).call
    end

    def initialize(message:, content:)
      @message = message
      @content = content
    end

    def call
      turn = @message.turn

      turn.with_lock do
        turn.reload
        raise_invalid!(turn, :selected_output_message, "must match the retry target") unless turn.selected_output_message_id == @message.id
        raise_invalid!(turn, :lifecycle_state, "must be failed or canceled to retry output") unless turn.failed? || turn.canceled?
        raise_invalid!(turn, :base, "cannot rewrite a fork-point output") if @message.reload.fork_point?

        retry_output = AgentMessage.create!(
          installation: turn.installation,
          conversation: turn.conversation,
          turn: turn,
          role: "agent",
          slot: "output",
          variant_index: turn.messages.where(slot: "output").maximum(:variant_index).to_i + 1,
          content: @content
        )

        turn.update!(
          selected_output_message: retry_output,
          lifecycle_state: "active"
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
