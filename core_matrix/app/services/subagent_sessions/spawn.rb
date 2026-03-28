module SubagentSessions
  class Spawn
    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, requested_by_turn:, content:, scope:, profile_key: nil, canonical_name: nil, nickname: nil, task_payload: {})
      @conversation = conversation
      @requested_by_turn = requested_by_turn
      @content = content
      @scope = scope
      @profile_key = profile_key
      @canonical_name = canonical_name
      @nickname = nickname
      @task_payload = task_payload.deep_stringify_keys
    end

    def call
      ApplicationRecord.transaction do
        @conversation.with_lock do
          validate_requested_by_turn!
          validate_spawn_visibility!
          Conversations::ValidateMutableState.call(
            conversation: @conversation,
            record: @conversation,
            retained_message: "must be retained for subagent spawn",
            active_message: "must be active for subagent spawn",
            closing_message: "must not spawn subagents while close is in progress"
          )

          child_conversation = Conversations::CreateThread.call(
            parent: @conversation,
            addressability: "agent_addressable"
          )
          session = SubagentSession.create!(
            installation: @conversation.installation,
            conversation: child_conversation,
            owner_conversation: @conversation,
            origin_turn: scope_turn? ? @requested_by_turn : nil,
            scope: @scope,
            profile_key: resolved_profile_key,
            canonical_name: @canonical_name,
            nickname: @nickname,
            parent_subagent_session: @conversation.subagent_session,
            depth: next_depth,
            last_known_status: "running"
          )
          child_turn = Turns::StartAgentTurn.call(
            conversation: child_conversation,
            content: @content,
            sender_kind: "owner_agent",
            sender_conversation: @conversation,
            agent_deployment: child_conversation.agent_deployment,
            resolved_config_snapshot: {},
            resolved_model_selection_snapshot: {}
          )
          workflow_run = Workflows::CreateForTurn.call(
            turn: child_turn,
            root_node_key: "subagent_step_1",
            root_node_type: "agent_task_run",
            decision_source: "system",
            metadata: {
              "subagent_session_id" => session.public_id,
              "requested_by_turn_id" => @requested_by_turn.public_id,
            },
            initial_task_kind: "subagent_step",
            initial_task_payload: @task_payload.presence || { "delivery_kind" => "subagent_spawn" },
            requested_by_turn: @requested_by_turn,
            subagent_session: session
          )
          agent_task_run = AgentTaskRun.find_by!(
            workflow_run: workflow_run,
            workflow_node: workflow_run.workflow_nodes.first,
            subagent_session: session,
            requested_by_turn: @requested_by_turn
          )

          serialize(
            session: session,
            conversation: child_conversation,
            turn: child_turn,
            workflow_run: workflow_run,
            agent_task_run: agent_task_run
          )
        end
      end
    end

    private

    def validate_requested_by_turn!
      return if @requested_by_turn.conversation_id == @conversation.id

      raise_invalid!(@conversation, :requested_by_turn, "must belong to the owner conversation")
    end

    def validate_spawn_visibility!
      RuntimeCapabilities::ComposeForConversation.visible_tool_entry!(
        conversation: @conversation,
        tool_name: "subagent_spawn"
      )
    rescue RuntimeCapabilities::ComposeForConversation::ToolNotVisibleError => error
      raise_invalid!(@conversation, :base, error.message)
    end

    def resolved_profile_key
      @resolved_profile_key ||= begin
        requested = @profile_key.presence
        if requested.present?
          raise_invalid!(@conversation, :profile_key, "must exist in the runtime profile catalog") unless profile_catalog.key?(requested)
          requested
        else
          default_subagent_profile_key
        end
      end
    end

    def default_subagent_profile_key
      metadata_default = profile_catalog.find do |_key, value|
        value.is_a?(Hash) && value["default_subagent_profile"] == true
      end&.first
      return metadata_default if metadata_default.present?

      profile_catalog.keys.find { |key| key != interactive_profile_key } ||
        interactive_profile_key
    end

    def interactive_profile_key
      runtime_contract.default_config_snapshot.dig("interactive", "profile") || "main"
    end

    def profile_catalog
      runtime_contract.profile_catalog
    end

    def runtime_contract
      @runtime_contract ||= RuntimeCapabilityContract.build(
        execution_environment: @conversation.execution_environment,
        capability_snapshot: @conversation.agent_deployment.active_capability_snapshot,
        core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
      )
    end

    def scope_turn?
      @scope.to_s == "turn"
    end

    def next_depth
      return 0 if @conversation.subagent_session.blank?

      @conversation.subagent_session.depth + 1
    end

    def serialize(session:, conversation:, turn:, workflow_run:, agent_task_run:)
      {
        "subagent_session_id" => session.public_id,
        "conversation_id" => conversation.public_id,
        "turn_id" => turn.public_id,
        "workflow_run_id" => workflow_run.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "profile_key" => session.profile_key,
        "scope" => session.scope,
        "parent_subagent_session_id" => session.parent_subagent_session&.public_id,
        "subagent_depth" => session.depth,
      }.compact
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end
  end
end
