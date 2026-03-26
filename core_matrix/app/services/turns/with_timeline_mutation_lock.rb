module Turns
  class WithTimelineMutationLock
    def self.call(*args, **kwargs, &block)
      new(*args, **kwargs).call(&block)
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
      current_conversation.with_lock do
        current_turn.with_lock do
          validated_turn = Turns::ValidateTimelineMutationTarget.call(
            turn: current_turn,
            record: @record,
            retained_attribute: @retained_attribute,
            retained_message: @retained_message,
            active_attribute: @active_attribute,
            active_message: @active_message,
            closing_attribute: @closing_attribute,
            closing_message: @closing_message,
            interrupted_attribute: @interrupted_attribute,
            interrupted_message: @interrupted_message
          )
          yield validated_turn
        end
      end
    end

    private

    def current_turn
      @current_turn ||= Turn.find(@turn.id)
    end

    def current_conversation
      @current_conversation ||= Conversation.find(current_turn.conversation_id)
    end
  end
end
