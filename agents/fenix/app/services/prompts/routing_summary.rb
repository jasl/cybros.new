module Prompts
  class RoutingSummary
    def self.call(...)
      new(...).call
    end

    def initialize(settings_payload:, catalog: ProfileCatalogLoader.default)
      @settings_payload = settings_payload.to_h.deep_stringify_keys
      @catalog = catalog
    end

    def call
      enabled_specialists = @catalog.enabled_specialists(Array(agent_subagent_settings["enabled_profile_keys"]))
      return nil if enabled_specialists.empty?

      lines = []
      lines << "Delegation mode: #{agent_subagent_settings["delegation_mode"].presence || "allow"}"

      enabled_keys = enabled_specialists.map(&:key)
      default_profile_key = agent_subagent_settings["default_profile_key"].presence
      default_profile_key = nil unless enabled_keys.include?(default_profile_key)
      lines << "Default specialist: #{default_profile_key}" if default_profile_key

      max_depth = core_matrix_subagent_settings["max_depth"]
      lines << "Max subagent depth: #{max_depth}" if max_depth.present?

      max_concurrent = core_matrix_subagent_settings["max_concurrent"]
      lines << "Max concurrent subagents: #{max_concurrent}" if max_concurrent.present?

      if core_matrix_subagent_settings.key?("allow_nested")
        lines << "Nested delegation: #{core_matrix_subagent_settings["allow_nested"] ? "allowed" : "disabled"}"
      end

      lines << "Enabled specialists:"
      enabled_specialists.each do |bundle|
        lines << "- #{bundle.key}: #{bundle.description}"
        bundle.when_to_use.each do |example|
          lines << "  when: #{example}"
        end
      end

      lines.join("\n")
    end

    private

    def agent_subagent_settings
      value = @settings_payload.dig("agent", "subagents")
      value.is_a?(Hash) ? value : {}
    end

    def core_matrix_subagent_settings
      value = @settings_payload.dig("core_matrix", "subagents")
      value.is_a?(Hash) ? value : {}
    end
  end
end
