module Conversations
  class ReconcileCloseOperation
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, occurred_at: Time.current, owned_subagent_connection_ids: nil, owned_subagent_conversation_ids: nil)
      @conversation = conversation
      @occurred_at = occurred_at
      @owned_subagent_connection_ids = owned_subagent_connection_ids
      @owned_subagent_conversation_ids = owned_subagent_conversation_ids
    end

    def call
      conversation = current_conversation

      ApplicationRecord.transaction do
        conversation.with_lock do
          locked_conversation = conversation.reload
          close_operation = locked_conversation.unfinished_close_operation
          next if close_operation.blank?

          Conversations::ProgressCloseRequests.call(
            conversation: locked_conversation,
            occurred_at: @occurred_at,
            owned_subagent_connection_ids: @owned_subagent_connection_ids
          )
          blocker_snapshot = Conversations::BlockerSnapshotQuery.call(
            conversation: locked_conversation,
            owned_subagent_connection_ids: @owned_subagent_connection_ids,
            owned_subagent_conversation_ids: @owned_subagent_conversation_ids
          )
          archive_if_mainline_cleared!(conversation: locked_conversation, close_operation:, blocker_snapshot:)
          close_operation.update!(reconciled_attributes(conversation: locked_conversation, close_operation:, blocker_snapshot:))
        end
      end

      conversation.reload
    end

    private

    def current_conversation
      @current_conversation ||= Conversation.find(@conversation.id)
    end

    def archive_if_mainline_cleared!(conversation:, close_operation:, blocker_snapshot:)
      return unless close_operation.intent_archive?
      return unless blocker_snapshot.mainline_clear?
      return unless conversation.active?

      conversation.update!(lifecycle_state: "archived")
    end

    def lifecycle_state_for(conversation:, close_operation:, blocker_snapshot:)
      return "quiescing" unless blocker_snapshot.mainline_clear?
      return "quiescing" if close_operation.intent_delete? && !conversation.deleted?
      return "disposing" if close_operation.intent_delete? && blocker_snapshot.dependency_blocked?
      return "disposing" if blocker_snapshot.tail_pending?
      return "degraded" if blocker_snapshot.tail_degraded?

      "completed"
    end

    def reconciled_attributes(conversation:, close_operation:, blocker_snapshot:)
      lifecycle_state = lifecycle_state_for(conversation:, close_operation:, blocker_snapshot:)

      {
        lifecycle_state: lifecycle_state,
        summary_payload: blocker_snapshot.close_summary.deep_stringify_keys,
        completed_at: ConversationCloseOperation::TERMINAL_STATES.include?(lifecycle_state) ? @occurred_at : nil,
      }
    end
  end
end
