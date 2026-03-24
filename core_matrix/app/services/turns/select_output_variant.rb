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
      raise_invalid!(turn, :lifecycle_state, "must be completed to select an output variant") unless turn.completed?
      raise_invalid!(turn, :base, "must target the selected tail output") unless turn.tail_in_active_timeline?

      turn.update!(selected_output_message: @message)
      turn
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
