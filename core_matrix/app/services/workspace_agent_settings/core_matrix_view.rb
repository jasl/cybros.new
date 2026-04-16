module WorkspaceAgentSettings
  class CoreMatrixView
    def self.build(...)
      new(...).build
    end

    def initialize(settings_payload:, default_settings:)
      @settings_payload = Schema.normalize_hash(settings_payload)
      @default_settings = Schema.normalize_hash(default_settings)
    end

    def build
      {
        "interactive_model_selector" => interactive_model_selector,
        "subagent_max_concurrent" => subagent_max_concurrent,
        "subagent_max_depth" => subagent_max_depth,
        "subagent_allow_nested" => subagent_allow_nested,
        "subagent_default_model_selector" => subagent_default_model_selector,
      }.compact
    end

    def interactive_model_selector
      core_matrix_settings.dig("interactive", "model_selector").presence
    end

    def subagent_max_concurrent
      integer_setting(core_matrix_settings.dig("subagents", "max_concurrent"))
    end

    def subagent_max_depth
      integer_setting(core_matrix_settings.dig("subagents", "max_depth"))
    end

    def subagent_allow_nested
      value = core_matrix_settings.dig("subagents", "allow_nested")
      return value if [true, false].include?(value)

      nil
    end

    def subagent_default_model_selector
      core_matrix_settings.dig("subagents", "default_model_selector").presence
    end

    def subagent_model_selector_for(label)
      return if label.blank?

      selectors = core_matrix_settings.dig("subagents", "label_model_selectors")
      return unless selectors.is_a?(Hash)

      selectors[label.to_s].presence
    end

    private

    def core_matrix_settings
      @core_matrix_settings ||= begin
        defaults = Schema.normalize_hash(@default_settings["core_matrix"])
        overrides = Schema.normalize_hash(@settings_payload["core_matrix"])
        defaults.deep_merge(overrides)
      end
    end

    def integer_setting(value)
      return if value.respond_to?(:blank?) ? value.blank? : value.nil?

      Integer(value, exception: false)
    end
  end
end
