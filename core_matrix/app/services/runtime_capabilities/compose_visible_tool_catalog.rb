module RuntimeCapabilities
  class ComposeVisibleToolCatalog
    SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES
    DEFAULT_SUBAGENT_PROFILE_ALIAS = RuntimeCapabilityContract::DEFAULT_SUBAGENT_PROFILE_ALIAS

    def initialize(conversation:, agent_program_version:, execution_runtime:)
      @conversation = conversation
      @agent_program_version = agent_program_version
      @execution_runtime = execution_runtime
    end

    def call
      apply_profile_mask(
        apply_subagent_policy(contract.effective_tool_catalog)
      ).then { |catalog| contextualize_tool_catalog(catalog) }.map(&:deep_dup)
    end

    def contract
      @contract ||= RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        agent_program_version: @agent_program_version,
        core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
      )
    end

    def current_profile_key
      @current_profile_key ||= begin
        @conversation.subagent_session&.profile_key ||
          contract.default_config_snapshot.dig("interactive", "profile") ||
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
      return tool_catalog unless current_profile.key?("allowed_tool_names")

      allowed_tool_names = Array(current_profile.fetch("allowed_tool_names"))
      tool_catalog.select { |entry| allowed_tool_names.include?(entry.fetch("tool_name")) }
    end

    def effective_subagent_policy
      contract.default_config_snapshot.fetch("subagents", {}).deep_merge(
        @conversation.override_payload.fetch("subagents", {})
      )
    end

    def current_profile
      contract.profile_catalog.fetch(current_profile_key, {})
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
      explicit_profile_keys = contract.profile_catalog.keys

      properties["profile_key"] = profile_key_schema.merge(
        "type" => "string",
        "enum" => [DEFAULT_SUBAGENT_PROFILE_ALIAS, *explicit_profile_keys].uniq,
        "description" => [
          profile_key_schema["description"],
          "Use #{DEFAULT_SUBAGENT_PROFILE_ALIAS.inspect} or omit this field to let the runtime choose the default subagent profile.",
          "Available explicit profiles: #{explicit_profile_keys.join(", ")}.",
        ].compact.join(" ").strip
      )

      entry.deep_dup.merge(
        "input_schema" => schema.merge("properties" => properties)
      )
    end

    def hide_subagent_spawn?
      return false if subagents_disabled?
      return false unless @conversation.subagent_session.present?
      return true if nested_spawning_disabled?

      max_depth = effective_subagent_policy["max_depth"]
      max_depth.present? && @conversation.subagent_session.depth >= max_depth.to_i
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
  end
end
