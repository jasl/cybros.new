module RuntimeFeatures
  class PolicyResolver
    def self.call(...)
      new(...).call
    end

    def self.all(...)
      new(...).all
    end

    def initialize(feature_key: nil, workspace: nil, agent_definition_version: nil)
      @feature_key = feature_key&.to_s
      @workspace = workspace
      @agent_definition_version = agent_definition_version || workspace&.agent&.current_agent_definition_version
    end

    def call
      raise ArgumentError, "feature_key is required" if @feature_key.blank?

      RuntimeFeaturePolicies::Registry.fetch(@feature_key).default_payload
        .deep_merge(runtime_default_features.fetch(@feature_key, {}))
        .deep_merge(workspace_override_features.fetch(@feature_key, {}))
    end

    def all
      RuntimeFeaturePolicies::Registry.feature_keys.each_with_object({}) do |feature_key, out|
        out[feature_key] = self.class.call(
          feature_key: feature_key,
          workspace: @workspace,
          agent_definition_version: @agent_definition_version
        )
      end
    end

    private

    def runtime_default_features
      RuntimeFeaturePolicies::RootSchema.normalized_runtime_defaults(@agent_definition_version&.default_canonical_config)
    end

    def workspace_override_features
      RuntimeFeaturePolicies::RootSchema.normalized_workspace_features(@workspace&.config)
    end
  end
end
