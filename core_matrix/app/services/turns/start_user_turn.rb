module Turns
  class StartUserTurn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, content:, agent_deployment:, resolved_config_snapshot:, resolved_model_selection_snapshot:)
      @conversation = conversation
      @content = content
      @agent_deployment = agent_deployment
      @resolved_config_snapshot = resolved_config_snapshot
      @resolved_model_selection_snapshot = resolved_model_selection_snapshot
    end

    def call
      raise_invalid!(@conversation, :purpose, "must be interactive for user turn entry") unless @conversation.interactive?
      raise_invalid!(@conversation, :lifecycle_state, "must be active for user turn entry") unless @conversation.active?

      @conversation.with_lock do
        turn = Turn.create!(
          installation: @conversation.installation,
          conversation: @conversation,
          agent_deployment: @agent_deployment,
          sequence: @conversation.turns.maximum(:sequence).to_i + 1,
          lifecycle_state: "active",
          origin_kind: "manual_user",
          origin_payload: {},
          source_ref_type: "User",
          source_ref_id: @conversation.workspace.user_id.to_s,
          pinned_deployment_fingerprint: @agent_deployment.fingerprint,
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

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
