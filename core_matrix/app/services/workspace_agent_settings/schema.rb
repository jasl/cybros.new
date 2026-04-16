module WorkspaceAgentSettings
  class Schema
    def self.schema_for(agent_definition_version:)
      normalize_hash(agent_definition_version&.workspace_agent_settings_schema)
    end

    def self.defaults_for(agent_definition_version:)
      normalize_hash(agent_definition_version&.default_workspace_agent_settings)
    end

    def self.normalize_hash(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end
  end
end
