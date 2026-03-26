module Turns
  class SelectOutputVariant
    def self.call(...)
      new(...).call
    end

    def initialize(message:)
      @message = message
    end

    def call
      turn = @message.turn

      raise_invalid!(turn, :slot, "must target an output message") unless @message.output?
      Turns::WithTimelineMutationLock.call(
        turn: turn,
        retained_message: "must be retained before selecting an output variant",
        active_message: "must belong to an active conversation to select an output variant",
        closing_message: "must not select an output variant while close is in progress",
        interrupted_message: "must not select an output variant after turn interruption"
      ) do |locked_turn|
        raise_invalid!(locked_turn, :lifecycle_state, "must be completed to select an output variant") unless locked_turn.completed?
        raise_invalid!(locked_turn, :base, "must target the selected tail output") unless locked_turn.tail_in_active_timeline?
        if locked_turn.selected_output_message&.fork_point? || @message.reload.fork_point?
          raise_invalid!(locked_turn, :base, "cannot rewrite a fork-point output")
        end

        locked_turn.update!(selected_output_message: @message)
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
