module Turns
  class StartAgentTurn
    ALLOWED_SENDER_KINDS = %w[owner_agent subagent_self system].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, sender_kind:, sender_conversation: nil, execution_runtime: nil, resolved_config_snapshot:, resolved_model_selection_snapshot:)
      @conversation = conversation
      @content = content
      @sender_kind = sender_kind
      @sender_conversation = sender_conversation
      @execution_runtime = execution_runtime
      @resolved_config_snapshot = resolved_config_snapshot
      @resolved_model_selection_snapshot = resolved_model_selection_snapshot
    end

    def call
      Conversations::WithConversationEntryLock.call(
        conversation: @conversation,
        retained_message: "must be retained for agent turn entry",
        active_message: "must be active for agent turn entry",
        closing_message: "must not accept agent turn entry while close is in progress"
      ) do |conversation|
        raise_invalid!(conversation, :purpose, "must be interactive for agent turn entry") unless conversation.interactive?
        SubagentConnections::ValidateAddressability.call(
          conversation: conversation,
          sender_kind: @sender_kind,
          rejection_message: "must be agent_addressable for agent turn entry"
        )
        validate_sender_kind!

        execution_identity = Turns::FreezeExecutionIdentity.call(
          conversation: conversation,
          execution_runtime: @execution_runtime
        )

        turn = Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_definition_version: execution_identity.agent_definition_version,
          execution_epoch: execution_identity.execution_epoch,
          execution_runtime: execution_identity.execution_runtime,
          execution_runtime_version: execution_identity.execution_runtime_version,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: "system_internal",
          origin_payload: sender_payload,
          source_ref_type: sender_source_ref_type,
          source_ref_id: sender_source_ref_id,
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
        turn
      end
    end

    private

    def validate_sender_kind!
      unless ALLOWED_SENDER_KINDS.include?(@sender_kind)
        raise_invalid!(@conversation, :sender_kind, "must be owner_agent, subagent_self, or system")
      end

      if @sender_kind == "owner_agent" && @sender_conversation != @conversation.subagent_connection&.owner_conversation
        raise_invalid!(@conversation, :sender_kind, "must match the owner conversation for owner_agent delivery")
      end

      if @sender_kind == "subagent_self" && @sender_conversation != @conversation
        raise_invalid!(@conversation, :sender_kind, "must match the target conversation for subagent_self delivery")
      end
    end

    def sender_payload
      {
        "sender_kind" => @sender_kind,
        "sender_conversation_id" => @sender_conversation&.public_id,
      }.compact
    end

    def sender_source_ref_type
      return "Conversation" if @sender_conversation.present?

      "System"
    end

    def sender_source_ref_id
      return @sender_conversation.public_id if @sender_conversation.present?

      "system"
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
