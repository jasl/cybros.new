module Conversations
  class FinalizeDeletion
    include Conversations::WorkQuiescenceGuard

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      return @conversation if @conversation.deleted? && @conversation.canonical_store_reference.blank?

      raise_invalid!(@conversation, :deletion_state, "must be pending delete before finalization") unless @conversation.pending_delete?

      ApplicationRecord.transaction do
        @conversation.with_lock do
          validate_quiescent!
          @conversation.canonical_store_reference&.destroy!
          @conversation.update!(deletion_state: "deleted")
          update_close_operation!
        end
      end

      CanonicalStores::GarbageCollectJob.perform_later
      @conversation.reload
    end

    private

    def validate_quiescent!
      ensure_mainline_stop_barrier_clear!(@conversation, stage: "final deletion")
    end

    def update_close_operation!
      close_operation = @conversation.unfinished_close_operation
      return if close_operation.blank?

      summary = Conversations::CloseSummaryQuery.call(conversation: @conversation)
      lifecycle_state = if summary.dig(:tail, :running_background_process_count).positive? || summary.dig(:tail, :detached_tool_process_count).positive?
        "disposing"
      elsif summary.dig(:tail, :degraded_close_count).positive?
        "degraded"
      else
        "completed"
      end
      close_operation.update!(
        lifecycle_state: lifecycle_state,
        summary_payload: summary.deep_stringify_keys,
        completed_at: ConversationCloseOperation::TERMINAL_STATES.include?(lifecycle_state) ? Time.current : nil
      )
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
