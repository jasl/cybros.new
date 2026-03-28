module Turns
  class StartAgentTurn
    ALLOWED_SENDER_KINDS = %w[owner_agent subagent_self system].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, sender_kind:, sender_conversation: nil, agent_deployment:, resolved_config_snapshot:, resolved_model_selection_snapshot:)
      @conversation = conversation
      @content = content
      @sender_kind = sender_kind
      @sender_conversation = sender_conversation
      @resolved_config_snapshot = resolved_config_snapshot
      @resolved_model_selection_snapshot = resolved_model_selection_snapshot
    end

    def call
      @conversation.with_lock do
        raise_invalid!(@conversation, :purpose, "must be interactive for agent turn entry") unless @conversation.interactive?
        SubagentSessions::ValidateAddressability.call(
          conversation: @conversation,
          sender_kind: @sender_kind,
          rejection_message: "must be agent_addressable for agent turn entry"
        )
        Turns::ValidateConversationTurnEntry.call(
          conversation: @conversation,
          entry_label: "agent turn entry",
          closing_message: "must not accept agent turn entry while close is in progress"
        )
        validate_sender_kind!
        agent_deployment = @conversation.agent_deployment

        turn = Turn.create!(
          installation: @conversation.installation,
          conversation: @conversation,
          agent_deployment: agent_deployment,
          sequence: @conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: "system_internal",
          origin_payload: sender_payload,
          source_ref_type: sender_source_ref_type,
          source_ref_id: sender_source_ref_id,
          pinned_deployment_fingerprint: agent_deployment.fingerprint,
          resolved_config_snapshot: @resolved_config_snapshot,
          resolved_model_selection_snapshot: @resolved_model_selection_snapshot
        )

        message = UserMessage.create!(
          installation: @conversation.installation,
          conversation: @conversation,
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

      if @sender_kind == "owner_agent" && @sender_conversation != @conversation.subagent_session&.owner_conversation
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
