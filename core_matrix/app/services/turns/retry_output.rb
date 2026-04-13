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
        target_message = Message.includes(:source_input_message).find(@message.id)

        raise_invalid!(locked_turn, :selected_output_message, "must match the retry target") unless locked_turn.selected_output_message_id == @message.id
        raise_invalid!(locked_turn, :lifecycle_state, "must be failed or canceled to retry output") unless locked_turn.failed? || locked_turn.canceled?
        raise_invalid!(locked_turn, :base, "must target the selected tail output") unless locked_turn.tail_in_active_timeline?
        raise_invalid!(locked_turn, :base, "cannot rewrite a fork-point output") if target_message.fork_point?

        source_input_message = target_message.source_input_message ||
          raise_invalid!(locked_turn, :selected_output_message, "must carry source input provenance")
        retry_output = Turns::CreateOutputVariant.call(
          turn: locked_turn,
          content: @content,
          source_input_message: source_input_message
        )

        Turns::PersistSelectionState.call(
          turn: locked_turn,
          selected_output_message: retry_output,
          lifecycle_state: "active",
        )
        Conversations::RefreshLatestTurnAnchors.call(
          conversation: locked_turn.conversation,
          turn: locked_turn,
          message: retry_output,
          activity_at: retry_output.created_at
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
