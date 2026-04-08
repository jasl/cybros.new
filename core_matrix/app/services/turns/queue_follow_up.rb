module Turns
  class QueueFollowUp
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, executor_program: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:, **_ignored)
      @conversation = conversation
      @content = content
      @executor_program = executor_program
      @resolved_config_snapshot = resolved_config_snapshot
      @resolved_model_selection_snapshot = resolved_model_selection_snapshot
    end

    def call
      Conversations::WithConversationEntryLock.call(
        conversation: @conversation,
        retained_message: "must be retained for follow up turn entry",
        active_message: "must be active for follow up turn entry",
        closing_message: "must not accept new turn entry while close is in progress"
      ) do |conversation|
        raise_invalid!(conversation, :purpose, "must be interactive for follow up turn entry") unless conversation.interactive?
        SubagentSessions::ValidateAddressability.call(
          conversation: conversation,
          sender_kind: "human",
          rejection_message: "must be owner_addressable for follow up turn entry"
        )

        unless conversation.turns.where(lifecycle_state: %w[queued active]).exists?
          raise_invalid!(conversation, :base, "must have active work before queueing follow up")
        end

        agent_program_version = Turns::FreezeProgramVersion.call(conversation: conversation)
        executor_program = Turns::SelectExecutorProgram.call(
          conversation: conversation,
          executor_program: @executor_program
        )

        turn = Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_program_version: agent_program_version,
          executor_program: executor_program,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "queued",
          origin_kind: "manual_user",
          origin_payload: {},
          source_ref_type: "User",
          source_ref_id: conversation.workspace.user.public_id,
          pinned_program_version_fingerprint: agent_program_version.fingerprint,
          resolved_config_snapshot: @resolved_config_snapshot,
          resolved_model_selection_snapshot: @resolved_model_selection_snapshot
        )

        message = UserMessage.create!(
          installation: conversation.installation,
          conversation: conversation,
          turn: turn,
          role: "user",
          slot: "input",
          variant_index: 0,
          content: @content
        )

        turn.update!(selected_input_message: message)
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
