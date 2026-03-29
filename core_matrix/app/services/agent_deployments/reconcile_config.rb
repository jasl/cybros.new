module AgentDeployments
  class ReconcileConfig
    Result = Struct.new(:reconciled_config, :report, keyword_init: true)

    RUNTIME_OWNED_CONFIG_KEYS = %w[interactive model_slots model_roles subagents].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(previous_default_config_snapshot:, next_config_schema_snapshot:, next_default_config_snapshot:)
      @previous_default_config_snapshot = previous_default_config_snapshot || {}
      @next_config_schema_snapshot = next_config_schema_snapshot || {}
      @next_default_config_snapshot = next_default_config_snapshot || {}
    end

    def call
      reconciled_config = @next_default_config_snapshot.deep_dup
      retained_keys = []

      allowed_selector_keys.each do |key|
        next unless @previous_default_config_snapshot.key?(key)

        merged_value = merge_value(@previous_default_config_snapshot[key], reconciled_config[key])
        next if merged_value == reconciled_config[key]

        reconciled_config[key] = merged_value
        retained_keys << key
      end

      Result.new(
        reconciled_config: reconciled_config,
        report: {
          "status" => retained_keys.any? ? "reconciled" : "exact",
          "retained_keys" => retained_keys,
        }
      )
    end

    private

    def allowed_selector_keys
      schema_properties.keys & RUNTIME_OWNED_CONFIG_KEYS
    end

    def schema_properties
      return {} unless @next_config_schema_snapshot.is_a?(Hash)

      @next_config_schema_snapshot.fetch("properties", {})
    end

    def merge_value(previous_value, next_value)
      return previous_value.deep_dup if next_value.nil?
      return previous_value.deep_merge(next_value) if previous_value.is_a?(Hash) && next_value.is_a?(Hash)

      next_value
    end
  end
end
