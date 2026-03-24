module Conversations
  class RollbackToTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, turn:)
      @conversation = conversation
      @turn = turn
    end

    def call
      raise_invalid!(@turn, :conversation, "must belong to the target conversation") unless @turn.conversation_id == @conversation.id

      ApplicationRecord.transaction do
        @conversation.turns
          .where("sequence > ?", @turn.sequence)
          .where.not(lifecycle_state: "canceled")
          .find_each do |later_turn|
            later_turn.update!(lifecycle_state: "canceled")
          end

        @turn
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
