module Turns
  class StartAutomationTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, origin_kind:, origin_payload:, source_ref_type:, source_ref_id:, idempotency_key:, external_event_key:, agent_deployment:, resolved_config_snapshot:, resolved_model_selection_snapshot:)
      @conversation = conversation
      @origin_kind = origin_kind
      @origin_payload = origin_payload
      @source_ref_type = source_ref_type
      @source_ref_id = source_ref_id
      @idempotency_key = idempotency_key
      @external_event_key = external_event_key
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
        agent_deployment = conversation.agent_deployment

        Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_deployment: agent_deployment,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: @origin_kind,
          origin_payload: @origin_payload,
          source_ref_type: @source_ref_type,
          source_ref_id: @source_ref_id,
          idempotency_key: @idempotency_key,
          external_event_key: @external_event_key,
          pinned_deployment_fingerprint: agent_deployment.fingerprint,
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
