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

      Turns::WithTimelineMutationLock.call(
        turn: turn,
        retained_message: "must be retained before rewriting output",
        active_message: "must belong to an active conversation to rewrite output",
        closing_message: "must not rewrite output while close is in progress",
        interrupted_message: "must not rewrite output after turn interruption"
      ) do |locked_turn|
        raise_invalid!(locked_turn, :selected_output_message, "must match the retry target") unless locked_turn.selected_output_message_id == @message.id
        raise_invalid!(locked_turn, :lifecycle_state, "must be failed or canceled to retry output") unless locked_turn.failed? || locked_turn.canceled?
        raise_invalid!(locked_turn, :base, "cannot rewrite a fork-point output") if @message.reload.fork_point?

        source_input_message = @message.reload.source_input_message ||
          raise_invalid!(locked_turn, :selected_output_message, "must carry source input provenance")
        retry_output = Turns::CreateOutputVariant.call(
          turn: locked_turn,
          content: @content,
          source_input_message: source_input_message
        )

        locked_turn.update!(
          selected_output_message: retry_output,
          lifecycle_state: "active"
        )
        locked_turn
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
