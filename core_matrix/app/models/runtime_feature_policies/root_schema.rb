module RuntimeFeaturePolicies
  class RootSchema
    def self.default_config
      { "features" => {} }
    end

    def self.default_features
      Registry.feature_keys.each_with_object({}) do |feature_key, out|
        out[feature_key] = Registry.fetch(feature_key).default_payload
      end
    end

    def self.json_schema
      {
        "$schema" => "https://json-schema.org/draft/2020-12/schema",
        "type" => "object",
        "additionalProperties" => false,
        "properties" => {
          "features" => {
            "type" => "object",
            "additionalProperties" => false,
            "properties" => Registry.feature_keys.each_with_object({}) do |feature_key, out|
              out[feature_key] = Registry.fetch(feature_key).json_schema
            end,
          },
        },
      }
    end

    def self.normalized_workspace_features(config)
      normalize_features(normalize_hash(config).fetch("features", {}))
    end

    def self.normalized_runtime_defaults(default_canonical_config)
      normalize_features(normalize_hash(default_canonical_config).fetch("features", {}))
    end

    def self.validate_config!(config)
      values = normalize_hash(config)
      features = values.fetch("features", {})
      raise ArgumentError, "features must be a hash" unless features.is_a?(Hash)

      validate_features!(features)
    end

    def self.validation_errors(config)
      validate_config!(config)
      []
    rescue ArgumentError => error
      [error.message]
    end

    def self.merge_feature_overrides(config:, feature_overrides:)
      values = normalize_hash(config)
      validate_features!(feature_overrides)
      features = normalized_workspace_features(values).deep_merge(normalize_features(feature_overrides))

      values.merge("features" => features)
    end

    def self.normalize_hash(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end

    def self.normalize_features(value)
      normalize_hash(value).slice(*Registry.feature_keys).each_with_object({}) do |(feature_key, payload), out|
        next unless payload.is_a?(Hash)

        out[feature_key] = Registry.fetch(feature_key).normalize(payload)
      end
    end

    def self.validate_features!(features)
      normalize_hash(features).each do |feature_key, payload|
        schema_class = Registry.find(feature_key)
        raise ArgumentError, "features.#{feature_key} is not supported" if schema_class.blank?

        schema_class.validate!(payload)
      end
    end
  end
end
