module SubagentConnections
  class Spawn
    include Conversations::CreationSupport
    DEFAULT_SUBAGENT_PROFILE_ALIAS = RuntimeCapabilityContract::DEFAULT_SUBAGENT_PROFILE_ALIAS

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, origin_turn:, content:, scope:, profile_key: nil, task_payload: {})
      @conversation = conversation
      @origin_turn = origin_turn
      @content = content
      @scope = scope
      @profile_key = profile_key
      @task_payload = task_payload.deep_stringify_keys
    end

    def call
      child_conversation = build_child_conversation(
        parent: @conversation,
        kind: "fork",
        addressability: "agent_addressable"
      )

      ApplicationRecord.transaction do
        Conversations::WithMutableStateLock.call(
          conversation: @conversation,
          record: child_conversation,
          retained_message: "must be retained for subagent spawn",
          active_message: "must be active for subagent spawn",
          closing_message: "must not spawn subagents while close is in progress"
        ) do |conversation|
          validate_origin_turn!(conversation:)
          validate_spawn_visibility!(conversation:)
          refresh_child_conversation_from_parent!(conversation: child_conversation, parent: conversation)
          child_conversation.save!
          initialize_child_conversation!(conversation: child_conversation, parent: conversation)

          session = SubagentConnection.create!(
            installation: conversation.installation,
            conversation: child_conversation,
            owner_conversation: conversation,
            origin_turn: scope_turn? ? @origin_turn : nil,
            scope: @scope,
            profile_key: resolved_profile_key(conversation:),
            parent_subagent_connection: conversation.subagent_connection,
            depth: next_depth(conversation:),
            observed_status: "running"
          )
          child_turn = Turns::StartAgentTurn.call(
            conversation: child_conversation,
            content: @content,
            sender_kind: "owner_agent",
            sender_conversation: conversation,
            resolved_config_snapshot: {},
            resolved_model_selection_snapshot: {}
          )
          workflow_run = Workflows::CreateForTurn.call(
            turn: child_turn,
            root_node_key: "subagent_step_1",
            root_node_type: "agent_task_run",
            decision_source: "system",
            metadata: {},
            selector_source: @origin_turn.resolved_model_selection_snapshot["selector_source"] || "conversation",
            selector: @origin_turn.normalized_selector,
            initial_kind: "subagent_step",
            initial_payload: initial_payload(conversation: conversation),
            origin_turn: @origin_turn,
            subagent_connection: session
          )
          agent_task_run = AgentTaskRun.find_by!(
            workflow_run: workflow_run,
            workflow_node: workflow_run.workflow_nodes.first,
            subagent_connection: session,
            origin_turn: @origin_turn
          )
          initialize_supervision_state!(session:, agent_task_run:)
          refresh_supervision_states!(owner_conversation: conversation, child_conversation: child_conversation)

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

    def validate_origin_turn!(conversation:)
      return if @origin_turn.conversation_id == conversation.id

      raise_invalid!(conversation, :origin_turn, "must belong to the owner conversation")
    end

    def validate_spawn_visibility!(conversation:)
      RuntimeCapabilities::PreviewForConversation.visible_tool_entry!(
        conversation: conversation,
        tool_name: "subagent_spawn"
      )
    rescue RuntimeCapabilities::PreviewForConversation::ToolNotVisibleError => error
      raise_invalid!(conversation, :base, error.message)
    end

    def resolved_profile_key(conversation:)
      @resolved_profile_key ||= begin
        requested = normalized_profile_key_request
        if requested.present?
          if requested == DEFAULT_SUBAGENT_PROFILE_ALIAS
            default_subagent_profile_key(conversation:)
          else
            raise_invalid!(conversation, :profile_key, "must exist in the runtime profile policy") unless profile_policy(conversation:).key?(requested)
            requested
          end
        else
          default_subagent_profile_key(conversation:)
        end
      end
    end

    def default_subagent_profile_key(conversation:)
      metadata_default = profile_policy(conversation:).find do |_key, value|
        value.is_a?(Hash) && value["default_subagent_profile"] == true
      end&.first
      return metadata_default if metadata_default.present?

      profile_policy(conversation:).keys.find { |key| key != interactive_profile_key(conversation:) } ||
        interactive_profile_key(conversation:)
    end

    def interactive_profile_key(conversation:)
      runtime_contract(conversation:).default_canonical_config.dig("interactive", "profile") || "main"
    end

    def profile_policy(conversation:)
      runtime_contract(conversation:).profile_policy
    end

    def runtime_contract(conversation:)
      @runtime_contract ||= RuntimeCapabilityContract.build(
        execution_runtime: execution_identity(conversation: conversation).execution_runtime,
        agent_definition_version: execution_identity(conversation: conversation).agent_definition_version,
        core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
      )
    end

    def execution_identity(conversation:)
      @execution_identity ||= Turns::FreezeExecutionIdentity.call(conversation: conversation)
    end

    def scope_turn?
      @scope.to_s == "turn"
    end

    def next_depth(conversation:)
      return 0 if conversation.subagent_connection.blank?

      conversation.subagent_connection.depth + 1
    end

    def serialize(session:, conversation:, turn:, workflow_run:, agent_task_run:)
      {
        "subagent_connection_id" => session.public_id,
        "conversation_id" => conversation.public_id,
        "turn_id" => turn.public_id,
        "workflow_run_id" => workflow_run.public_id,
        "agent_task_run_id" => agent_task_run.public_id,
        "profile_key" => session.profile_key,
        "scope" => session.scope,
        "parent_subagent_connection_id" => session.parent_subagent_connection&.public_id,
        "subagent_depth" => session.depth,
      }.compact
    end

    def initial_payload(conversation:)
      @initial_payload ||= begin
        payload = @task_payload.deep_dup
        payload["delivery_kind"] ||= "subagent_spawn"
        payload["delegation_package"] = delegation_package(conversation:)
        payload
      end
    end

    def delegation_package(conversation:)
      {
        "owner_conversation_id" => conversation.public_id,
        "origin_turn_id" => @origin_turn.public_id,
        "scope" => @scope,
        "profile_key" => resolved_profile_key(conversation:),
        "content" => @content,
      }.compact
    end

    def initialize_supervision_state!(session:, agent_task_run:)
      summary = @content.to_s.strip.tr("\n", " ").truncate(SupervisionStateFields::HUMAN_SUMMARY_MAX_LENGTH)

      session.update!(
        supervision_state: "running",
        focus_kind: "general",
        request_summary: summary,
        current_focus_summary: summary,
        last_progress_at: Time.current,
        supervision_payload: {}
      )
      agent_task_run.update!(
        supervision_state: "running",
        focus_kind: "general",
        request_summary: summary,
        current_focus_summary: summary,
        last_progress_at: Time.current,
        supervision_payload: {}
      )
    end

    def refresh_supervision_states!(owner_conversation:, child_conversation:)
      [owner_conversation, child_conversation].uniq.each do |conversation|
        Conversations::UpdateSupervisionState.call(
          conversation: conversation,
          occurred_at: Time.current
        )
      end
    end

    def raise_invalid!(record, attribute, message)
      record.errors.add(attribute, message)
      raise ActiveRecord::RecordInvalid, record
    end

    def normalized_profile_key_request
      @profile_key.to_s.strip.presence
    end
  end
end
