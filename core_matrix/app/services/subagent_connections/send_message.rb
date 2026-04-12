module SubagentConnections
  class SendMessage
    EVENT_KIND = "subagent.message_appended".freeze
    ALLOWED_SENDER_KINDS = %w[owner_agent subagent_self system].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, sender_kind:, sender_conversation: nil)
      @conversation = conversation
      @content = content
      @sender_kind = sender_kind
      @sender_conversation = sender_conversation
    end

    def call
      Conversations::WithMutableStateLock.call(
        conversation: @conversation,
        record: @conversation,
        retained_message: "must be retained for subagent delivery",
        active_message: "must be active for subagent delivery",
        closing_message: "must not accept subagent delivery while close is in progress"
      ) do |conversation|
        validate_session_mutable!(conversation:)
        SubagentConnections::ValidateAddressability.call(
          conversation: conversation,
          sender_kind: @sender_kind,
          rejection_message: "must be agent_addressable for subagent delivery"
        )
        validate_sender_kind!(conversation:)
        execution_identity = Turns::FreezeExecutionIdentity.call(conversation: conversation)

        turn = Turn.create!(
          installation: conversation.installation,
          conversation: conversation,
          agent_definition_version: execution_identity.agent_definition_version,
          execution_runtime: execution_identity.execution_runtime,
          execution_runtime_version: execution_identity.execution_runtime_version,
          sequence: conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "completed",
          origin_kind: "system_internal",
          origin_payload: sender_payload,
          source_ref_type: sender_source_ref_type,
          source_ref_id: sender_source_ref_id,
          pinned_agent_definition_fingerprint: execution_identity.pinned_agent_definition_fingerprint,
          agent_config_version: execution_identity.agent_config_version,
          agent_config_content_fingerprint: execution_identity.agent_config_content_fingerprint,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {}
        )

        message = AgentMessage.create!(
          installation: conversation.installation,
          conversation: conversation,
          turn: turn,
          role: "agent",
          slot: "output",
          variant_index: 0,
          content: @content
        )

        turn.update!(selected_output_message: message)

        ConversationEvents::Project.call(
          conversation: conversation,
          turn: turn,
          source: message,
          event_kind: EVENT_KIND,
          payload: {
            "message_id" => message.public_id,
            "sender_kind" => @sender_kind,
            "sender_conversation_id" => @sender_conversation&.public_id,
          }.compact
        )

        message
      end
    end

    private

    def validate_sender_kind!(conversation:)
      unless ALLOWED_SENDER_KINDS.include?(@sender_kind)
        raise_invalid!(conversation:, attribute: :sender_kind, message: "must be owner_agent, subagent_self, or system")
      end

      if @sender_kind == "owner_agent" && @sender_conversation != conversation.subagent_connection&.owner_conversation
        raise_invalid!(conversation:, attribute: :sender_kind, message: "must match the owner conversation for owner_agent delivery")
      end

      if @sender_kind == "subagent_self" && @sender_conversation != conversation
        raise_invalid!(conversation:, attribute: :sender_kind, message: "must match the target conversation for subagent_self delivery")
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

    def validate_session_mutable!(conversation:)
      session = conversation.subagent_connection
      return if session.blank? || session.close_open?

      raise_invalid!(conversation:, attribute: :base, message: "must not accept subagent delivery while session close is in progress")
    end

    def raise_invalid!(conversation:, attribute:, message:)
      conversation.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, conversation
    end
  end
end
