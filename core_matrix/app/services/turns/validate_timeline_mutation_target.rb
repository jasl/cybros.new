module Turns
  class ValidateTimelineMutationTarget
    def self.call(...)
      new(...).call
    end

    def initialize(
      turn:,
      record: nil,
      retained_attribute: :deletion_state,
      retained_message:,
      active_attribute: :lifecycle_state,
      active_message:,
      closing_attribute: :base,
      closing_message:,
      interrupted_attribute: :base,
      interrupted_message:
    )
      @turn = turn
      @record = record
      @retained_attribute = retained_attribute
      @retained_message = retained_message
      @active_attribute = active_attribute
      @active_message = active_message
      @closing_attribute = closing_attribute
      @closing_message = closing_message
      @interrupted_attribute = interrupted_attribute
      @interrupted_message = interrupted_message
    end

    def call
      Conversations::ValidateMutableState.call(
        conversation: current_turn.conversation,
        record: invalid_record,
        retained_attribute: @retained_attribute,
        retained_message: @retained_message,
        active_attribute: @active_attribute,
        active_message: @active_message,
        closing_attribute: @closing_attribute,
        closing_message: @closing_message
      )

      return current_turn unless current_turn.cancellation_reason_kind == "turn_interrupted"

      invalid_record.errors.add(@interrupted_attribute, @interrupted_message)
      raise ActiveRecord::RecordInvalid, invalid_record
    end

    private

    def current_turn
      @current_turn ||=
        if @turn.persisted? && !@turn.destroyed?
          @turn.reload
        else
          @turn
        end
    end

    def invalid_record
      @invalid_record ||= @record || current_turn
    end
  end
end
