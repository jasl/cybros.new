module WorkspacePolicies
  class Upsert
    def self.call(...)
      new(...).call
    end

    def initialize(
      workspace:,
      workspace_agent:,
      disabled_capabilities:,
      default_execution_runtime: :__preserve__,
      features: :__preserve__
    )
      @workspace = workspace
      @workspace_agent = workspace_agent
      @disabled_capabilities = Array(disabled_capabilities).map(&:to_s).uniq
      @default_execution_runtime = default_execution_runtime
      @features = features
    end

    def call
      agent = @workspace_agent.agent
      available_capabilities = agent.present? ? WorkspacePolicies::Capabilities.available_for(agent: agent) : []
      unless (@disabled_capabilities - available_capabilities).empty?
        raise ArgumentError, "disabled_capabilities must be a subset of the available capabilities"
      end

      config = WorkspaceFeatures::Schema.normalize_hash(@workspace.config)
      if @features != :__preserve__
        feature_overrides = normalize_features!(@features)
        config = WorkspaceFeatures::Schema.merge_feature_overrides(
          config: config,
          feature_overrides: feature_overrides
        )
        WorkspaceFeatures::Schema.validate_config!(config)
      end

      ApplicationRecord.transaction do
        updates = { disabled_capabilities: @disabled_capabilities }
        updates[:config] = config if @features != :__preserve__
        @workspace.update!(updates)
        if @default_execution_runtime != :__preserve__
          @workspace_agent.update!(default_execution_runtime: @default_execution_runtime)
        end
        @workspace
      end
    end

    private

    def normalize_features!(features)
      values = features.respond_to?(:to_unsafe_h) ? features.to_unsafe_h : features
      raise ArgumentError, "features must be a hash" unless values.is_a?(Hash)

      values.deep_stringify_keys
    end
  end
end
