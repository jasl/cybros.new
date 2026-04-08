module Turns
  class StartAutomationTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, origin_kind:, origin_payload:, source_ref_type:, source_ref_id:, idempotency_key:, external_event_key:, executor_program: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:, **_ignored)
      @conversation = conversation
      @origin_kind = origin_kind
      @origin_payload = origin_payload
      @source_ref_type = source_ref_type
      @source_ref_id = source_ref_id
      @idempotency_key = idempotency_key
      @external_event_key = external_event_key
      @executor_program = executor_program
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

        agent_program_version = Turns::FreezeProgramVersion.call(conversation: conversation)
        executor_program = Turns::SelectExecutorProgram.call(
          conversation: conversation,
          executor_program: @executor_program
        )

        Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_program_version: agent_program_version,
          executor_program: executor_program,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: @origin_kind,
          origin_payload: @origin_payload,
          source_ref_type: @source_ref_type,
          source_ref_id: @source_ref_id,
          idempotency_key: @idempotency_key,
          external_event_key: @external_event_key,
          pinned_program_version_fingerprint: agent_program_version.fingerprint,
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
