module WorkspaceFeatures
  class Schema
    def self.default_features
      RuntimeFeaturePolicies::RootSchema.default_features
    end

    def self.default_config
      RuntimeFeaturePolicies::RootSchema.default_config
    end

    def self.normalized_workspace_features(config)
      RuntimeFeaturePolicies::RootSchema.normalized_workspace_features(config)
    end

    def self.normalized_runtime_defaults(default_canonical_config)
      RuntimeFeaturePolicies::RootSchema.normalized_runtime_defaults(default_canonical_config)
    end

    def self.validate_config!(config)
      RuntimeFeaturePolicies::RootSchema.validate_config!(config)
    end

    def self.validation_errors(config)
      RuntimeFeaturePolicies::RootSchema.validation_errors(config)
    end

    def self.merge_feature_overrides(config:, feature_overrides:)
      RuntimeFeaturePolicies::RootSchema.merge_feature_overrides(
        config: config,
        feature_overrides: feature_overrides
      )
    end

    def self.normalize_hash(value)
      RuntimeFeaturePolicies::RootSchema.normalize_hash(value)
    end

    def self.normalize_features(value)
      RuntimeFeaturePolicies::RootSchema.normalize_features(value)
    end
  end
end
