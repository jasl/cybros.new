module Conversations
  class ReconcileCloseOperation
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current)
      @conversation = conversation
      @occurred_at = occurred_at
    end

    def call
      ApplicationRecord.transaction do
        @conversation.with_lock do
          close_operation = @conversation.unfinished_close_operation
          next if close_operation.blank?

          Conversations::ProgressCloseRequests.call(
            conversation: @conversation,
            occurred_at: @occurred_at
          )
          blocker_snapshot = Conversations::BlockerSnapshotQuery.call(conversation: @conversation)
          archive_if_mainline_cleared!(close_operation, blocker_snapshot)
          close_operation.update!(reconciled_attributes(close_operation, blocker_snapshot))
        end
      end

      @conversation.reload
    end

    private

    def archive_if_mainline_cleared!(close_operation, blocker_snapshot)
      return unless close_operation.intent_archive?
      return unless blocker_snapshot.mainline_clear?
      return unless @conversation.active?

      @conversation.update!(lifecycle_state: "archived")
    end

    def lifecycle_state_for(close_operation, blocker_snapshot)
      return "quiescing" unless blocker_snapshot.mainline_clear?
      return "quiescing" if close_operation.intent_delete? && !@conversation.deleted?
      return "disposing" if close_operation.intent_delete? && blocker_snapshot.dependency_blocked?
      return "disposing" if blocker_snapshot.tail_pending?
      return "degraded" if blocker_snapshot.tail_degraded?

      "completed"
    end

    def reconciled_attributes(close_operation, blocker_snapshot)
      lifecycle_state = lifecycle_state_for(close_operation, blocker_snapshot)

      {
        lifecycle_state: lifecycle_state,
        summary_payload: blocker_snapshot.close_summary.deep_stringify_keys,
        completed_at: ConversationCloseOperation::TERMINAL_STATES.include?(lifecycle_state) ? @occurred_at : nil,
      }
    end
  end
end
