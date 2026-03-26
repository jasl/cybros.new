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

          summary = Conversations::CloseSummaryQuery.call(conversation: @conversation)
          archive_if_mainline_cleared!(close_operation, summary)
          close_operation.update!(reconciled_attributes(close_operation, summary))
        end
      end

      @conversation.reload
    end

    private

    def archive_if_mainline_cleared!(close_operation, summary)
      return unless close_operation.intent_archive?
      return unless mainline_clear?(summary)
      return unless @conversation.active?

      @conversation.update!(lifecycle_state: "archived")
    end

    def lifecycle_state_for(close_operation, summary)
      return "quiescing" unless mainline_clear?(summary)
      return "quiescing" if close_operation.intent_delete? && !@conversation.deleted?
      return "disposing" if tail_pending?(summary)
      return "degraded" if tail_degraded?(summary)

      "completed"
    end

    def reconciled_attributes(close_operation, summary)
      lifecycle_state = lifecycle_state_for(close_operation, summary)

      {
        lifecycle_state: lifecycle_state,
        summary_payload: summary.deep_stringify_keys,
        completed_at: ConversationCloseOperation::TERMINAL_STATES.include?(lifecycle_state) ? @occurred_at : nil,
      }
    end

    def mainline_clear?(summary)
      summary.dig(:mainline, :active_turn_count).zero? &&
        summary.dig(:mainline, :active_workflow_count).zero? &&
        summary.dig(:mainline, :active_agent_task_count).zero? &&
        summary.dig(:mainline, :open_blocking_interaction_count).zero? &&
        summary.dig(:mainline, :running_turn_command_count).zero? &&
        summary.dig(:mainline, :running_subagent_count).zero?
    end

    def tail_pending?(summary)
      summary.dig(:tail, :running_background_process_count).positive? ||
        summary.dig(:tail, :detached_tool_process_count).positive?
    end

    def tail_degraded?(summary)
      summary.dig(:tail, :degraded_close_count).positive?
    end
  end
end
