module Turns
  class QueueFollowUp
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, execution_runtime: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:)
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
          lifecycle_state: "queued",
          origin_kind: "manual_user",
          origin_payload: {},
          source_ref_type: "User",
          source_ref_id: conversation.workspace.user.public_id,
          pinned_agent_definition_fingerprint: execution_identity.pinned_agent_definition_fingerprint,
          agent_config_version: execution_identity.agent_config_version,
          agent_config_content_fingerprint: execution_identity.agent_config_content_fingerprint,
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
        conversation.refresh_latest_anchors!(activity_at: message.created_at)
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
