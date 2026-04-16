module SubagentConnections
  class Spawn
    include Conversations::CreationSupport
    DEFAULT_SUBAGENT_PROFILE_ALIAS = RuntimeCapabilityContract::DEFAULT_SUBAGENT_PROFILE_ALIAS
    ChildSelectorChoice = Struct.new(:selector_source, :selector, :resolved_hint, keyword_init: true)

    def self.call(...)
      new(...).call
    end

    def initialize(conversation:, origin_turn:, content:, scope:, profile_key: nil, model_selector_hint: nil, task_payload: {})
      @conversation = conversation
      @origin_turn = origin_turn
      @content = content
      @scope = scope
      @profile_key = profile_key
      @model_selector_hint = model_selector_hint
      @task_payload = task_payload.deep_stringify_keys
    end

    def call
      child_conversation = build_child_conversation(
        parent: @conversation,
        kind: "fork",
        entry_policy_payload: Conversation.agent_internal_entry_policy_payload
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
          validate_max_concurrent_subagents!(conversation:)
          refresh_child_conversation_from_parent!(conversation: child_conversation, parent: conversation)
          child_conversation.save!
          initialize_child_conversation!(conversation: child_conversation, parent: conversation)

          session = SubagentConnection.create!(
            installation: conversation.installation,
            user: conversation.user,
            workspace: conversation.workspace,
            agent: conversation.agent,
            conversation: child_conversation,
            owner_conversation: conversation,
            origin_turn: scope_turn? ? @origin_turn : nil,
            scope: @scope,
            profile_key: resolved_profile_key(conversation:),
            resolved_model_selector_hint: resolved_model_selector_hint(conversation:),
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
            selector_source: child_selector_choice(conversation:).selector_source,
            selector: child_selector_choice(conversation:).selector,
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
      RuntimeCapabilities::ComposeForTurn.visible_tool_entry!(
        turn: @origin_turn,
        tool_name: "subagent_spawn"
      )
    rescue RuntimeCapabilities::ComposeForTurn::ToolNotVisibleError => error
      raise_invalid!(conversation, :base, error.message)
    end

    def resolved_profile_key(conversation:)
      @resolved_profile_key ||= begin
        requested = normalized_profile_key_request
        if requested.present?
          if requested == DEFAULT_SUBAGENT_PROFILE_ALIAS
            default_subagent_profile_key(conversation:)
          else
            raise_invalid!(conversation, :profile_key, "must be enabled for the current mount") unless enabled_subagent_profile_keys(conversation:).include?(requested)
            requested
          end
        else
          default_subagent_profile_key(conversation:)
        end
      end
    end

    def default_subagent_profile_key(conversation:)
      enabled_keys = enabled_subagent_profile_keys(conversation:)
      configured_default = profile_settings_view(conversation:)["default_subagent_profile_key"]
      return configured_default if configured_default.present? && enabled_keys.include?(configured_default)

      metadata_default = enabled_keys.find do |key|
        value = profile_policy(conversation:)[key]
        value.is_a?(Hash) && value["default_subagent_profile"] == true
      end
      return metadata_default if metadata_default.present?

      enabled_keys.first ||
        interactive_profile_key(conversation:)
    end

    def interactive_profile_key(conversation:)
      profile_settings_view(conversation:)["interactive_profile_key"] ||
        runtime_contract(conversation:).default_canonical_config.dig("interactive", "profile") ||
        runtime_contract(conversation:).default_canonical_config.dig("interactive", "default_profile_key") ||
        "main"
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

    def enabled_subagent_profile_keys(conversation:)
      explicit_enabled = profile_settings_view(conversation:).key?("enabled_subagent_profile_keys")
      return Array(profile_settings_view(conversation:)["enabled_subagent_profile_keys"]) - [interactive_profile_key(conversation:)] if explicit_enabled

      profile_policy(conversation:).keys - [interactive_profile_key(conversation:)]
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
        "model_selector_hint" => session.resolved_model_selector_hint,
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
        "model_selector_hint" => resolved_model_selector_hint(conversation:),
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

    def resolved_model_selector_hint(conversation:)
      @resolved_model_selector_hint ||= child_selector_choice(conversation:).resolved_hint
    end

    def validate_max_concurrent_subagents!(conversation:)
      max_concurrent = profile_settings_view(conversation:)["max_concurrent_subagents"]
      return if max_concurrent.blank?

      active_children = conversation.owned_subagent_connections.close_pending_or_open.count
      return if active_children < max_concurrent

      raise_invalid!(conversation, :base, "has reached the configured subagent concurrency limit")
    end

    def profile_settings_view(conversation:)
      @profile_settings_view ||= begin
        frozen_view = @origin_turn.execution_contract&.workspace_agent_profile_settings
        source = frozen_view.presence || conversation.workspace_agent&.profile_settings_view || {}
        source.deep_stringify_keys
      end
    end

    def child_selector_choice(conversation:)
      @child_selector_choice ||= begin
        chosen = soft_selector_candidates(conversation:).filter_map do |candidate|
          result = effective_catalog(conversation:).resolve_selector(selector: candidate)
          next unless result.usable?

          ChildSelectorChoice.new(
            selector_source: "subagent_spawn",
            selector: result.normalized_selector,
            resolved_hint: result.normalized_selector
          )
        end.first
        if chosen.present?
          chosen
        else
          fallback_selector = @origin_turn.normalized_selector
          ChildSelectorChoice.new(
            selector_source: @origin_turn.resolved_model_selection_snapshot["selector_source"] || "conversation",
            selector: fallback_selector,
            resolved_hint: fallback_selector.presence
          )
        end
      end
    end

    def soft_selector_candidates(conversation:)
      [
        normalized_model_selector_request,
        profile_model_selector_override(conversation:),
        default_model_selector_override(conversation:),
      ].compact.uniq
    end

    def normalized_model_selector_request
      @model_selector_hint.to_s.strip.presence
    end

    def profile_model_selector_override(conversation:)
      selectors = profile_settings_view(conversation:)["subagent_model_selectors"]
      return unless selectors.is_a?(Hash)

      selectors[resolved_profile_key(conversation:).to_s].presence
    end

    def default_model_selector_override(conversation:)
      profile_settings_view(conversation:)["default_subagent_model_selector"].presence ||
        profile_settings_view(conversation:)["default_subagent_model_selector_hint"].presence
    end

    def effective_catalog(conversation:)
      @effective_catalog ||= ProviderCatalog::EffectiveCatalog.new(
        installation: conversation.installation,
        env: Rails.env
      )
    end
  end
end
