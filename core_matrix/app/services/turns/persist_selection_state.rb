module Turns
  class PersistSelectionState
    def self.call(...)
      new(...).call
    end

    def initialize(turn:, selected_input_message: turn.selected_input_message, selected_output_message: turn.selected_output_message, lifecycle_state: turn.lifecycle_state)
      @turn = turn
      @selected_input_message = selected_input_message
      @selected_output_message = selected_output_message
      @lifecycle_state = lifecycle_state
    end

    def call
      updated_at = Time.current

      @turn.selected_input_message = @selected_input_message
      @turn.selected_output_message = @selected_output_message
      @turn.lifecycle_state = @lifecycle_state
      @turn.updated_at = updated_at
      @turn.update_columns(
        selected_input_message_id: @selected_input_message&.id,
        selected_output_message_id: @selected_output_message&.id,
        lifecycle_state: @lifecycle_state,
        updated_at: updated_at,
      )
    end
  end
end
