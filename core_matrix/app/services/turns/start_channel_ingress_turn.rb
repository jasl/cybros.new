module Turns
  class StartChannelIngressTurn
    ROOT_NODE_KEY = "turn_step".freeze
    ROOT_NODE_TYPE = "turn_step".freeze
    DECISION_SOURCE = "system".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(
      conversation:,
      channel_inbound_message:,
      content:,
      origin_payload:,
      selector_source:,
      selector:,
      execution_runtime: nil
    )
      @conversation = conversation
      @channel_inbound_message = channel_inbound_message
      @content = content
      @origin_payload = origin_payload
      @selector_source = selector_source
      @selector = selector
      @execution_runtime = execution_runtime
    end

    def call
      accepted_at = Time.current

      Conversations::WithConversationEntryLock.call(
        conversation: @conversation,
        retained_message: "must be retained for channel ingress turn entry",
        active_message: "must be active for channel ingress turn entry",
        lock_message: "must be mutable for channel ingress turn entry",
        closing_message: "must not accept new turn entry while close is in progress"
      ) do |conversation|
        raise_invalid!(conversation, :purpose, "must be interactive for channel ingress turn entry") unless conversation.interactive?
        raise_invalid!(conversation, :entry_policy_payload, "must allow channel ingress turn entry") unless conversation.allows_entry_surface?("channel_ingress")
        SubagentConnections::ValidateAddressability.call(
          conversation: conversation,
          sender_kind: "human",
          rejection_message: "must allow main transcript entry for channel ingress turn entry"
        )

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
          origin_kind: "channel_ingress",
          origin_payload: normalized_origin_payload,
          source_ref_type: "ChannelInboundMessage",
          source_ref_id: @channel_inbound_message.public_id,
          pinned_agent_definition_fingerprint: execution_identity.pinned_agent_definition_fingerprint,
          agent_config_version: execution_identity.agent_config_version,
          agent_config_content_fingerprint: execution_identity.agent_config_content_fingerprint,
          resolved_config_snapshot: {},
          resolved_model_selection_snapshot: {},
          workflow_bootstrap_state: "pending",
          workflow_bootstrap_payload: workflow_bootstrap_payload,
          workflow_bootstrap_failure_payload: {},
          workflow_bootstrap_requested_at: accepted_at,
          workflow_bootstrap_started_at: nil,
          workflow_bootstrap_finished_at: nil
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

        Turns::PersistSelectionState.call(turn: turn, selected_input_message: message)
        Conversations::RefreshLatestTurnAnchors.call(
          conversation: conversation,
          turn: turn,
          message: message,
          activity_at: message.created_at
        )
        Conversations::ProjectTurnBootstrapState.call(turn: turn)
        turn
      end
    end

    private

    def normalized_origin_payload
      values = @origin_payload.respond_to?(:to_unsafe_h) ? @origin_payload.to_unsafe_h : @origin_payload
      raise ArgumentError, "origin_payload must be a hash" unless values.is_a?(Hash)

      values.deep_stringify_keys
    end

    def workflow_bootstrap_payload
      {
        "selector_source" => @selector_source,
        "selector" => @selector,
        "root_node_key" => ROOT_NODE_KEY,
        "root_node_type" => ROOT_NODE_TYPE,
        "decision_source" => DECISION_SOURCE,
        "metadata" => {},
      }
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
