module WorkspaceFeatures
  class Resolver
    def self.call(...)
      new(...).call
    end

    def initialize(workspace: nil, agent_definition_version: nil)
      @workspace = workspace
      @agent_definition_version = agent_definition_version || workspace&.agent&.current_agent_definition_version
    end

    def call
      Schema.default_features
        .deep_merge(runtime_default_features)
        .deep_merge(workspace_override_features)
    end

    private

    def runtime_default_features
      Schema.normalized_runtime_defaults(@agent_definition_version&.default_canonical_config)
    end

    def workspace_override_features
      Schema.normalized_workspace_features(@workspace&.config)
    end
  end
end
