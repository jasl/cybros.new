module WorkspacePolicies
  class Upsert
    def self.call(...)
      new(...).call
    end

    def initialize(
      workspace:,
      disabled_capabilities:,
      default_execution_runtime: :__preserve__,
      metadata: :__preserve__
    )
      @workspace = workspace
      @disabled_capabilities = Array(disabled_capabilities).map(&:to_s).uniq
      @default_execution_runtime = default_execution_runtime
      @metadata = metadata
    end

    def call
      available_capabilities = WorkspacePolicies::Capabilities.available_for(agent: @workspace.agent)
      unless (@disabled_capabilities - available_capabilities).empty?
        raise ArgumentError, "disabled_capabilities must be a subset of the available capabilities"
      end

      config = @workspace.config_with_defaults
      if @metadata != :__preserve__
        metadata = normalize_metadata!(@metadata)
        config = @workspace.merged_config_with_metadata(metadata:)
        validate_title_bootstrap_config!(config)
      end

      ApplicationRecord.transaction do
        updates = { disabled_capabilities: @disabled_capabilities }
        updates[:default_execution_runtime] = @default_execution_runtime if @default_execution_runtime != :__preserve__
        updates[:config] = config if @metadata != :__preserve__
        @workspace.update!(updates)
        @workspace
      end
    end

    private

    def normalize_metadata!(metadata)
      values = metadata.respond_to?(:to_unsafe_h) ? metadata.to_unsafe_h : metadata
      raise ArgumentError, "metadata must be a hash" unless values.is_a?(Hash)

      values.deep_stringify_keys
    end

    def validate_title_bootstrap_config!(config)
      metadata = config.fetch("metadata", {})
      unless metadata.is_a?(Hash)
        raise ArgumentError, "metadata must be a hash"
      end

      title_bootstrap = metadata.fetch("title_bootstrap", {})
      unless title_bootstrap.is_a?(Hash)
        raise ArgumentError, "metadata.title_bootstrap must be a hash"
      end

      enabled = title_bootstrap["enabled"]
      mode = title_bootstrap["mode"]

      unless enabled == true || enabled == false
        raise ArgumentError, "metadata.title_bootstrap.enabled must be true or false"
      end

      unless Workspace::TITLE_BOOTSTRAP_MODES.include?(mode)
        raise ArgumentError, "metadata.title_bootstrap.mode must be runtime_first or embedded_only"
      end
    end
  end
end
