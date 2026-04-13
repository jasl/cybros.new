module Turns
  class StartAutomationTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, origin_kind:, origin_payload:, source_ref_type:, source_ref_id:, idempotency_key:, external_event_key:, execution_runtime: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:)
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

        execution_identity = Turns::FreezeExecutionIdentity.call(
          conversation: conversation,
          execution_runtime: @execution_runtime
        )

        turn = Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          user: conversation.user,
          workspace: conversation.workspace,
          agent: conversation.agent,
          agent_definition_version: execution_identity.agent_definition_version,
          execution_epoch: execution_identity.execution_epoch,
          execution_runtime: execution_identity.execution_runtime,
          execution_runtime_version: execution_identity.execution_runtime_version,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: @origin_kind,
          origin_payload: @origin_payload,
          source_ref_type: @source_ref_type,
          source_ref_id: @source_ref_id,
          idempotency_key: @idempotency_key,
          external_event_key: @external_event_key,
          pinned_agent_definition_fingerprint: execution_identity.pinned_agent_definition_fingerprint,
          agent_config_version: execution_identity.agent_config_version,
          agent_config_content_fingerprint: execution_identity.agent_config_content_fingerprint,
          resolved_config_snapshot: @resolved_config_snapshot,
          resolved_model_selection_snapshot: @resolved_model_selection_snapshot
        )

        Conversations::RefreshLatestTurnAnchors.call(
          conversation: conversation,
          turn: turn,
          activity_at: turn.created_at
        )
        turn
      end
    end

    private

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
