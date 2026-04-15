module Prompts
  class RoutingSummary
    def self.call(...)
      new(...).call
    end

    def initialize(profile_settings:, catalog: ProfileCatalogLoader.default)
      @profile_settings = profile_settings.to_h.deep_stringify_keys
      @catalog = catalog
    end

    def call
      enabled_specialists = @catalog.enabled_specialists(@profile_settings["enabled_subagent_profile_keys"])
      return nil if enabled_specialists.empty?

      lines = []
      lines << "Delegation mode: #{@profile_settings["delegation_mode"].presence || "allow"}"

      enabled_keys = enabled_specialists.map(&:key)
      default_profile_key = @profile_settings["default_subagent_profile_key"].presence
      default_profile_key = nil unless enabled_keys.include?(default_profile_key)
      lines << "Default specialist: #{default_profile_key}" if default_profile_key

      max_depth = @profile_settings["max_subagent_depth"]
      lines << "Max subagent depth: #{max_depth}" if max_depth.present?

      max_concurrent = @profile_settings["max_concurrent_subagents"]
      lines << "Max concurrent subagents: #{max_concurrent}" if max_concurrent.present?

      if @profile_settings.key?("allow_nested_subagents")
        lines << "Nested delegation: #{@profile_settings["allow_nested_subagents"] ? "allowed" : "disabled"}"
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
  end
end
