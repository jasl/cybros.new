module RuntimeCapabilities
  class ComposeVisibleToolCatalog
    SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

    def initialize(conversation:, agent_definition_version: nil, execution_runtime:, turn: nil)
      @conversation = conversation
      @agent_definition_version = agent_definition_version
      @execution_runtime = execution_runtime
      @turn = turn
    end

    def call
      contextualize_tool_catalog(
        apply_subagent_policy(contract.effective_tool_catalog)
      ).map(&:deep_dup)
    end

    def contract
      @contract ||= RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        agent_definition_version: @agent_definition_version,
        core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
      )
    end

    def current_profile_key
      @current_profile_key ||= @conversation.subagent_connection&.profile_key
    end

    def effective_subagent_policy
      @effective_subagent_policy ||= begin
        contract.default_canonical_config.fetch("subagents", {}).slice("enabled").deep_merge(
          workspace_agent_subagent_policy_overrides
        ).deep_merge(
          @conversation.override_payload.fetch("subagents", {})
        )
      end
    end

    private

    def apply_subagent_policy(tool_catalog)
      filtered_catalog = tool_catalog
      filtered_catalog = filtered_catalog.reject { |entry| subagent_tool?(entry.fetch("tool_name")) } if subagents_disabled?
      filtered_catalog = filtered_catalog.reject { |entry| entry.fetch("tool_name") == "subagent_spawn" } if hide_subagent_spawn?
      filtered_catalog
    end

    def contextualize_tool_catalog(tool_catalog)
      tool_catalog.map do |entry|
        next entry unless entry.fetch("tool_name") == "subagent_spawn"

        contextualize_subagent_spawn_entry(entry)
      end
    end

    def contextualize_subagent_spawn_entry(entry)
      schema = entry.fetch("input_schema", {}).deep_dup
      properties = schema.fetch("properties", {}).deep_dup
      model_selector_hint_schema = properties.fetch("model_selector_hint", {}).deep_dup

      properties["model_selector_hint"] = model_selector_hint_schema.merge(
        "type" => "string",
        "description" => [
          model_selector_hint_schema["description"],
          "Optional resolved model selector hint for the spawned subagent.",
        ].compact.join(" ").strip
      )

      entry.deep_dup.merge(
        "input_schema" => schema.merge("properties" => properties)
      )
    end

    def hide_subagent_spawn?
      return false if subagents_disabled?
      return false unless @conversation.subagent_connection.present?
      return true if nested_spawning_disabled?

      max_depth = effective_subagent_policy["max_depth"]
      max_depth.present? && @conversation.subagent_connection.depth >= max_depth.to_i
    end

    def nested_spawning_disabled?
      effective_subagent_policy["allow_nested"] == false
    end

    def subagents_disabled?
      effective_subagent_policy["enabled"] == false
    end

    def subagent_tool?(tool_name)
      SUBAGENT_TOOL_NAMES.include?(tool_name)
    end

    def workspace_agent_subagent_policy_overrides
      {}.tap do |overrides|
        allow_nested = core_matrix_settings.subagent_allow_nested
        max_depth = core_matrix_settings.subagent_max_depth

        overrides["allow_nested"] = allow_nested unless allow_nested.nil?
        overrides["max_depth"] = max_depth unless max_depth.nil?
      end
    end

    def core_matrix_settings
      @core_matrix_settings ||= begin
        settings_payload, default_settings =
          if @turn&.execution_contract.present?
            [
              @turn.execution_contract.workspace_agent_settings_payload,
              @turn.execution_contract.agent_definition_version&.default_workspace_agent_settings || {},
            ]
          else
            [
              @conversation.workspace_agent&.settings_payload_view,
              @conversation.workspace_agent&.default_settings_payload || contract.default_workspace_agent_settings,
            ]
          end

        WorkspaceAgentSettings::CoreMatrixView.new(
          settings_payload: settings_payload,
          default_settings: default_settings
        )
      end
    end
  end
end
