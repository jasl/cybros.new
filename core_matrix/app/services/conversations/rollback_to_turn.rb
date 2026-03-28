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

      Turns::WithTimelineActionLock.call(
        turn: @turn,
        before_phrase: "rolling back the conversation",
        action_phrase: "roll back the timeline"
      ) do |turn|
        ApplicationRecord.transaction do
          Conversations::ValidateTimelineSuffixSupersession.call(
            conversation: turn.conversation,
            turn: turn
          )
          turn.conversation.turns
            .where("sequence > ?", turn.sequence)
            .where.not(lifecycle_state: "canceled")
            .find_each do |later_turn|
              later_turn.update!(lifecycle_state: "canceled")
            end

          prune_superseded_support_state!(turn)
          turn
        end
      end
    end

    private

    def prune_superseded_support_state!(turn)
      dropped_segments = turn.conversation.conversation_summary_segments
        .includes(:end_message, :superseded_segments)
        .select { |segment| superseded_after_rollback?(segment, turn) }
      dropped_segment_ids = dropped_segments.map(&:id)

      if dropped_segment_ids.any?
        turn.conversation.conversation_summary_segments
          .where(superseded_by_id: dropped_segment_ids)
          .update_all(superseded_by_id: nil)
      end

      ConversationImport.where(summary_segment_id: dropped_segment_ids).find_each(&:destroy!)

      turn.conversation.conversation_imports
        .includes(:source_message, summary_segment: :end_message)
        .find_each do |conversation_import|
          conversation_import.destroy! if drop_import_after_rollback?(conversation_import, dropped_segment_ids, turn)
        end

      dropped_segments.each(&:destroy!)
    end

    def superseded_after_rollback?(segment, turn)
      return false unless segment.end_message.conversation_id == turn.conversation_id

      segment.end_message.turn.sequence > turn.sequence
    end

    def drop_import_after_rollback?(conversation_import, dropped_segment_ids, turn)
      return true if dropped_segment_ids.include?(conversation_import.summary_segment_id)
      return false if conversation_import.source_message.blank?
      return false unless conversation_import.source_message.conversation_id == turn.conversation_id

      conversation_import.source_message.turn.sequence > turn.sequence
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
