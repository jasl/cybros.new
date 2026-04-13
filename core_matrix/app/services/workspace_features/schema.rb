module WorkspaceFeatures
  class Schema
    FEATURE_MODES = %w[runtime_first embedded_only].freeze
    FEATURE_DEFAULTS = {
      "title_bootstrap" => {
        "enabled" => true,
        "mode" => "runtime_first",
      },
      "prompt_compaction" => {
        "enabled" => true,
        "mode" => "runtime_first",
      },
    }.freeze

    def self.default_features
      FEATURE_DEFAULTS.deep_dup
    end

    def self.default_config
      { "features" => {} }
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

    def self.validate_features!(features)
      values = normalize_hash(features)

      values.each do |feature_name, feature_payload|
        raise ArgumentError, "features.#{feature_name} is not supported" unless FEATURE_DEFAULTS.key?(feature_name)
        raise ArgumentError, "features.#{feature_name} must be a hash" unless feature_payload.is_a?(Hash)

        validate_enabled!(feature_name, feature_payload) if feature_payload.key?("enabled")
        validate_mode!(feature_name, feature_payload) if feature_payload.key?("mode")
      end
    end

    def self.merge_feature_overrides(config:, feature_overrides:)
      values = normalize_hash(config)
      features = normalized_workspace_features(values).deep_merge(normalize_features(feature_overrides))

      values.merge("features" => features)
    end

    def self.normalize_hash(value)
      value.is_a?(Hash) ? value.deep_stringify_keys : {}
    end

    def self.normalize_features(value)
      normalize_hash(value).slice(*FEATURE_DEFAULTS.keys)
    end

    def self.validate_enabled!(feature_name, feature_payload)
      enabled = feature_payload["enabled"]
      return if enabled == true || enabled == false

      raise ArgumentError, "features.#{feature_name}.enabled must be true or false"
    end

    def self.validate_mode!(feature_name, feature_payload)
      mode = feature_payload["mode"]
      return if FEATURE_MODES.include?(mode)

      raise ArgumentError, "features.#{feature_name}.mode must be runtime_first or embedded_only"
    end

    private_class_method :validate_enabled!, :validate_mode!
  end
end
