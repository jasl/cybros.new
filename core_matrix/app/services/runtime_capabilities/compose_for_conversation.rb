module RuntimeCapabilities
  class ComposeForConversation
    ToolNotVisibleError = Class.new(StandardError)
    SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

    def self.call(...)
      new(...).call
    end

    def self.visible_tool_entry!(conversation:, tool_name:)
      new(conversation: conversation).visible_tool_entry!(tool_name:)
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def call
      contract.conversation_payload(
        execution_environment_id: @conversation.execution_environment.public_id,
        agent_deployment_id: @conversation.agent_deployment.public_id
      ).merge(
        "tool_catalog" => visible_tool_catalog
      )
    end

    def visible_tool_entry!(tool_name:)
      visible_tool_catalog.find { |entry| entry.fetch("tool_name") == tool_name } ||
        raise(ToolNotVisibleError, "#{tool_name} is not visible for conversation #{@conversation.public_id}")
    end

    private

    def contract
      @contract ||= RuntimeCapabilityContract.build(
        execution_environment: @conversation.execution_environment,
        capability_snapshot: @conversation.agent_deployment.active_capability_snapshot,
        core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG
      )
    end

    def visible_tool_catalog
      @visible_tool_catalog ||= apply_profile_mask(
        apply_subagent_policy(contract.effective_tool_catalog)
      ).map(&:deep_dup)
    end

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

    def current_profile_key
      @conversation.subagent_session&.profile_key || contract.default_config_snapshot.dig("interactive", "profile") || "main"
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
