module Turns
  class QueueFollowUp
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, execution_runtime: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:, **_ignored)
      @conversation = conversation
      @content = content
      @execution_runtime = execution_runtime
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
        SubagentConnections::ValidateAddressability.call(
          conversation: conversation,
          sender_kind: "human",
          rejection_message: "must be owner_addressable for follow up turn entry"
        )

        unless conversation.turns.where(lifecycle_state: %w[queued active]).exists?
          raise_invalid!(conversation, :base, "must have active work before queueing follow up")
        end

        agent_snapshot = Turns::FreezeAgentSnapshot.call(conversation: conversation)
        execution_runtime = Turns::SelectExecutionRuntime.call(
          conversation: conversation,
          execution_runtime: @execution_runtime
        )

        turn = Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_snapshot: agent_snapshot,
          execution_runtime: execution_runtime,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "queued",
          origin_kind: "manual_user",
          origin_payload: {},
          source_ref_type: "User",
          source_ref_id: conversation.workspace.user.public_id,
          pinned_agent_snapshot_fingerprint: agent_snapshot.fingerprint,
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
