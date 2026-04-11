module Turns
  class StartAutomationTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, origin_kind:, origin_payload:, source_ref_type:, source_ref_id:, idempotency_key:, external_event_key:, execution_runtime: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:, **_ignored)
      @conversation = conversation
      @origin_kind = origin_kind
      @origin_payload = origin_payload
      @source_ref_type = source_ref_type
      @source_ref_id = source_ref_id
      @idempotency_key = idempotency_key
      @external_event_key = external_event_key
      @execution_runtime = execution_runtime
      @resolved_config_snapshot = resolved_config_snapshot
      @resolved_model_selection_snapshot = resolved_model_selection_snapshot
    end

    def call
      Conversations::WithConversationEntryLock.call(
        conversation: @conversation,
        retained_message: "must be retained for automation turn entry",
        active_message: "must be active for automation turn entry",
        closing_message: "must not accept new turn entry while close is in progress"
      ) do |conversation|
        raise_invalid!(conversation, :purpose, "must be automation for automation turn entry") unless conversation.automation?

        agent_snapshot = Turns::FreezeAgentSnapshot.call(conversation: conversation)
        execution_runtime = Turns::SelectExecutionRuntime.call(
          conversation: conversation,
          execution_runtime: @execution_runtime
        )

        Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_snapshot: agent_snapshot,
          execution_runtime: execution_runtime,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: @origin_kind,
          origin_payload: @origin_payload,
          source_ref_type: @source_ref_type,
          source_ref_id: @source_ref_id,
          idempotency_key: @idempotency_key,
          external_event_key: @external_event_key,
          pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
          resolved_config_snapshot: @resolved_config_snapshot,
          resolved_model_selection_snapshot: @resolved_model_selection_snapshot
        )
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
