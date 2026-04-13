module Turns
  class PersistSelectionState
    UNSPECIFIED = Object.new.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(turn:, selected_input_message: UNSPECIFIED, selected_output_message: UNSPECIFIED, lifecycle_state: UNSPECIFIED)
      @turn = turn
      @selected_input_message = selected_input_message
      @selected_output_message = selected_output_message
      @lifecycle_state = lifecycle_state
    end

    def call
      updated_at = Time.current
      selected_input_message_id = specified?(@selected_input_message) ? @selected_input_message&.id : @turn.selected_input_message_id
      selected_output_message_id = specified?(@selected_output_message) ? @selected_output_message&.id : @turn.selected_output_message_id
      lifecycle_state = specified?(@lifecycle_state) ? @lifecycle_state : @turn.lifecycle_state

      @turn.selected_input_message = @selected_input_message if specified?(@selected_input_message)
      @turn.selected_output_message = @selected_output_message if specified?(@selected_output_message)
      @turn.lifecycle_state = lifecycle_state
      @turn.updated_at = updated_at
      @turn.update_columns(
        selected_input_message_id: selected_input_message_id,
        selected_output_message_id: selected_output_message_id,
        lifecycle_state: lifecycle_state,
        updated_at: updated_at,
      )
    end

    private

    def specified?(value)
      !value.equal?(UNSPECIFIED)
    end
  end
end
