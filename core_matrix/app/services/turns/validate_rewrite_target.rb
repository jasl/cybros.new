module Turns
  class ValidateRewriteTarget
    def self.call(...)
      new(...).call
    end

    def initialize(turn:)
      @turn = turn
    end

    def call
      validate_retained!
      validate_active_conversation!
      validate_not_closing!
      validate_not_interrupted!

      current_turn
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

    def current_conversation
      @current_conversation ||=
        if current_turn.conversation.persisted? && !current_turn.conversation.destroyed?
          current_turn.conversation.reload
        else
          current_turn.conversation
        end
    end

    def validate_retained!
      return if current_conversation.retained?

      raise_invalid!(:deletion_state, "must be retained before rewriting output")
    end

    def validate_active_conversation!
      return if current_conversation.active?

      raise_invalid!(:lifecycle_state, "must belong to an active conversation to rewrite output")
    end

    def validate_not_closing!
      return unless current_conversation.closing?

      raise_invalid!(:base, "must not rewrite output while close is in progress")
    end

    def validate_not_interrupted!
      return unless current_turn.cancellation_reason_kind == "turn_interrupted"

      raise_invalid!(:base, "must not rewrite output after turn interruption")
    end

    def raise_invalid!(attribute, message)
      current_turn.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, current_turn
    end
  end
end
