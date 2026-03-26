module Conversations
  class RequestClose
    include Conversations::RetentionGuard

    INTENT_CONFIG = {
      "archive" => {
        queued_turn_reason: "conversation_archived",
        background_request_kind: "archive_force_quiesce",
        close_reason_kind: "conversation_archived",
      },
      "delete" => {
        queued_turn_reason: "conversation_deleted",
        background_request_kind: "deletion_force_quiesce",
        close_reason_kind: "conversation_deleted",
      },
    }.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, intent_kind:, occurred_at: Time.current)
      @conversation = conversation
      @intent_kind = intent_kind
      @occurred_at = occurred_at
    end

    def call
      config = INTENT_CONFIG.fetch(@intent_kind)

      ApplicationRecord.transaction do
        @conversation.with_lock do
          ensure_conversation_retained!(@conversation, message: "must be retained before close") if @intent_kind == "archive"
          close_operation = find_or_create_close_operation!
          apply_immediate_state!
          cancel_queued_turns!(reason_kind: config.fetch(:queued_turn_reason))
          request_turn_interrupts!
          request_background_process_closes!(
            request_kind: config.fetch(:background_request_kind),
            reason_kind: config.fetch(:close_reason_kind)
          )
          refresh_close_operation!(close_operation)
        end
      end

      @conversation.reload
    end

    private

    def find_or_create_close_operation!
      existing = @conversation.unfinished_close_operation
      return existing if existing.present? && existing.intent_kind == @intent_kind

      if existing.present?
        raise_invalid!(existing, :intent_kind, "must not change while a close operation is unfinished")
      end

      ConversationCloseOperation.create!(
        installation: @conversation.installation,
        conversation: @conversation,
        intent_kind: @intent_kind,
        lifecycle_state: "requested",
        requested_at: @occurred_at,
        summary_payload: {}
      )
    end

    def apply_immediate_state!
      return unless @intent_kind == "delete"
      return if @conversation.deleted?

      @conversation.update!(
        deletion_state: "pending_delete",
        deleted_at: @conversation.deleted_at || @occurred_at
      )
    end

    def cancel_queued_turns!(reason_kind:)
      Turn.where(conversation: @conversation, lifecycle_state: "queued").update_all(
        lifecycle_state: "canceled",
        cancellation_requested_at: @occurred_at,
        cancellation_reason_kind: reason_kind,
        updated_at: @occurred_at
      )
    end

    def request_turn_interrupts!
      Turn.where(conversation: @conversation, lifecycle_state: "active").find_each do |turn|
        Conversations::RequestTurnInterrupt.call(turn: turn, occurred_at: @occurred_at)
      end
    end

    def request_background_process_closes!(request_kind:, reason_kind:)
      ProcessRun.where(conversation: @conversation, lifecycle_state: "running", kind: "background_service").find_each do |process_run|
        next unless process_run.close_open?

        AgentControl::CreateResourceCloseRequest.call(
          resource: process_run,
          request_kind: request_kind,
          reason_kind: reason_kind,
          strictness: "graceful",
          grace_deadline_at: @occurred_at + 30.seconds,
          force_deadline_at: @occurred_at + 60.seconds
        )
      end
    end

    def refresh_close_operation!(close_operation)
      summary = Conversations::CloseSummaryQuery.call(conversation: @conversation)
      lifecycle_state = close_operation_lifecycle_state(summary)
      attributes = {
        lifecycle_state: lifecycle_state,
        summary_payload: summary.deep_stringify_keys,
      }

      if ConversationCloseOperation::TERMINAL_STATES.include?(lifecycle_state)
        attributes[:completed_at] = @occurred_at
      elsif lifecycle_state == "disposing"
        attributes[:completed_at] = nil
      end

      close_operation.update!(attributes)
    end

    def close_operation_lifecycle_state(summary)
      return "quiescing" unless mainline_clear?(summary)
      return "quiescing" if @intent_kind == "delete" && !@conversation.deleted?

      if @intent_kind == "archive" && @conversation.active?
        @conversation.update!(lifecycle_state: "archived")
      end

      return "disposing" if tail_pending?(summary)
      return "degraded" if tail_degraded?(summary)

      "completed"
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

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
