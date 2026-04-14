module WorkspacePolicies
  module Capabilities
    KEYS = %w[
      supervision
      detailed_progress
      side_chat
      control
      regenerate
      swipe
    ].freeze
    FENIX_DISABLED = %w[regenerate swipe].freeze

    module_function

    def available_for(agent:)
      reflected_surface = current_definition_version_for(agent)&.reflected_surface || {}
      explicit = normalize_capabilities(
        reflected_surface["workspace_capabilities"] ||
        reflected_surface["available_workspace_capabilities"] ||
        reflected_surface.dig("capabilities", "workspace")
      )
      available = explicit.presence || KEYS
      available -= FENIX_DISABLED if agent.key.to_s == "fenix"
      normalize_dependencies(available)
    end

    def current_definition_version_for(agent)
      return agent.current_agent_definition_version if agent[:current_agent_definition_version_id].present?
      return agent.published_agent_definition_version if agent[:published_agent_definition_version_id].present?

      nil
    end

    def disabled_for(workspace:)
      normalize_capabilities(workspace.disabled_capabilities)
    end

    def effective_for(workspace:, agent: nil)
      available = available_for(agent: agent || workspace.agent)
      disabled = disabled_for(workspace:) & available
      normalize_dependencies(available - disabled)
    end

    def projection_attributes_for(workspace:, agent: nil)
      available = available_for(agent: agent || workspace.agent)
      disabled = disabled_for(workspace:) & available
      effective = normalize_dependencies(available - disabled)

      {
        supervision_enabled: effective.include?("supervision"),
        detailed_progress_enabled: effective.include?("detailed_progress"),
        side_chat_enabled: effective.include?("side_chat"),
        control_enabled: effective.include?("control"),
      }
    end

    def normalize_capabilities(values)
      Array(values).map(&:to_s).uniq & KEYS
    end

    def normalize_dependencies(capabilities)
      normalized = capabilities.dup
      normalized -= %w[detailed_progress side_chat control] unless normalized.include?("supervision")
      normalized -= %w[control] unless normalized.include?("side_chat")
      normalized
    end
  end
end
