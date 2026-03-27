module Conversations
  class RequestClose
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
          if @intent_kind == "archive"
            Conversations::ValidateRetainedState.call(
              conversation: @conversation,
              record: @conversation,
              message: "must be retained before close"
            )
          end
          find_or_create_close_operation!
          apply_immediate_state!
          cancel_queued_turns!(reason_kind: config.fetch(:queued_turn_reason))
          request_turn_interrupts!
          request_background_process_closes!(
            request_kind: config.fetch(:background_request_kind),
            reason_kind: config.fetch(:close_reason_kind)
          )
        end

        Conversations::ReconcileCloseOperation.call(
          conversation: @conversation,
          occurred_at: @occurred_at
        )
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
          **close_request_deadlines
        )
      end
    end

    def close_request_deadlines
      @close_request_deadlines ||= CloseRequestSchedule.deadlines_for(occurred_at: @occurred_at)
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
