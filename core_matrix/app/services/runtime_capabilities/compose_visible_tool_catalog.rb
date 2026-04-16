module RuntimeCapabilities
  class ComposeVisibleToolCatalog
    SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES
    DEFAULT_SUBAGENT_PROFILE_ALIAS = RuntimeCapabilityContract::DEFAULT_SUBAGENT_PROFILE_ALIAS

    def initialize(conversation:, agent_definition_version: nil, execution_runtime:, turn: nil)
      @conversation = conversation
      @agent_definition_version = agent_definition_version
      @execution_runtime = execution_runtime
      @turn = turn
    end

    def call
      apply_profile_mask(
        apply_subagent_policy(contract.effective_tool_catalog)
      ).then { |catalog| contextualize_tool_catalog(catalog) }.map(&:deep_dup)
    end

    def contract
      @contract ||= RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        agent_definition_version: @agent_definition_version,
        core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
      )
    end

    def current_profile_key
      @current_profile_key ||= begin
        explicit_profile_key = explicit_turn_profile_key

        @conversation.subagent_connection&.profile_key ||
          (explicit_profile_key if explicit_profile_key.present? && contract.profile_policy.key?(explicit_profile_key)) ||
          profile_settings_view["interactive_profile_key"] ||
          contract.default_canonical_config.dig("interactive", "profile") ||
          contract.default_canonical_config.dig("interactive", "default_profile_key") ||
          "main"
      end
    end

    private

    def apply_subagent_policy(tool_catalog)
      filtered_catalog = tool_catalog
      filtered_catalog = filtered_catalog.reject { |entry| subagent_tool?(entry.fetch("tool_name")) } if subagents_disabled?
      filtered_catalog = filtered_catalog.reject { |entry| entry.fetch("tool_name") == "subagent_spawn" } if hide_subagent_spawn?
      filtered_catalog
    end

    def apply_profile_mask(tool_catalog)
      RuntimeCapabilities::ProfileToolMask.call(
        tool_catalog: tool_catalog,
        profile: current_profile
      )
    end

    def current_profile
      contract.profile_policy.fetch(current_profile_key, {})
    end

    def explicit_turn_profile_key
      return if @turn.blank?

      selector_source = @turn.resolved_model_selection_snapshot["selector_source"].presence ||
        @turn.workflow_bootstrap_payload["selector_source"]
      return if selector_source.blank? || selector_source == "conversation"

      selector = @turn.resolved_model_selection_snapshot["normalized_selector"].presence ||
        @turn.workflow_bootstrap_payload["selector"]
      return unless selector.to_s.start_with?("role:")

      selector.delete_prefix("role:")
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
      profile_key_schema = properties.fetch("profile_key", {}).deep_dup
      model_selector_hint_schema = properties.fetch("model_selector_hint", {}).deep_dup
      explicit_profile_keys = enabled_subagent_profile_keys

      properties["profile_key"] = profile_key_schema.merge(
        "type" => "string",
        "enum" => [DEFAULT_SUBAGENT_PROFILE_ALIAS, *explicit_profile_keys].uniq,
        "description" => [
          profile_key_schema["description"],
          "Use #{DEFAULT_SUBAGENT_PROFILE_ALIAS.inspect} or omit this field to let the runtime choose the default subagent profile.",
          "Available explicit profiles: #{explicit_profile_keys.join(", ")}.",
        ].compact.join(" ").strip
      )
      properties["model_selector_hint"] = model_selector_hint_schema.merge(
        "type" => "string",
        "description" => [
          model_selector_hint_schema["description"],
          "Optional resolved model selector hint for the spawned specialist.",
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
      effective_subagent_policy["enabled"] == false || enabled_subagent_profile_keys.empty?
    end

    def subagent_tool?(tool_name)
      SUBAGENT_TOOL_NAMES.include?(tool_name)
    end

    def enabled_subagent_profile_keys
      explicit_enabled = profile_settings_view.key?("enabled_subagent_profile_keys")
      return Array(profile_settings_view["enabled_subagent_profile_keys"]) - [mounted_interactive_profile_key] if explicit_enabled

      contract.profile_policy.keys - [mounted_interactive_profile_key]
    end

    def mounted_interactive_profile_key
      profile_settings_view["interactive_profile_key"] ||
        contract.default_canonical_config.dig("interactive", "profile") ||
        contract.default_canonical_config.dig("interactive", "default_profile_key") ||
        "main"
    end

    def workspace_agent_subagent_policy_overrides
      {}.tap do |overrides|
        if profile_settings_view.key?("allow_nested_subagents")
          overrides["allow_nested"] = profile_settings_view["allow_nested_subagents"]
        end
        if profile_settings_view["max_subagent_depth"].present?
          overrides["max_depth"] = profile_settings_view["max_subagent_depth"]
        end
      end
    end

    def profile_settings_view
      @profile_settings_view ||= begin
        frozen_view = @turn&.execution_contract&.workspace_agent_profile_settings
        source = frozen_view.presence || @conversation.workspace_agent&.profile_settings_view || {}
        source.deep_stringify_keys
      end
    end

    def effective_subagent_policy
      contract.default_canonical_config.fetch("subagents", {}).deep_merge(
        @conversation.override_payload.fetch("subagents", {})
      ).deep_merge(
        workspace_agent_subagent_policy_overrides
      )
    end
  end
end
