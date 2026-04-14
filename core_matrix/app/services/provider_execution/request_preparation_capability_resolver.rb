module ProviderExecution
  class RequestPreparationCapabilityResolver
    SUPPORTED_CONSULTATION_MODES = %w[direct_optional direct_required none].freeze
    SUPPORTED_WORKFLOW_EXECUTION = %w[supported unsupported].freeze

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:)
      @agent_definition_version = agent_definition_version
    end

    def call
      {
        "prompt_compaction" => resolve_prompt_compaction,
      }
    end

    private

    def resolve_prompt_compaction
      entry = @agent_definition_version&.request_preparation_contract&.fetch("prompt_compaction", nil)
      return unavailable_prompt_compaction if entry.blank? || !entry.is_a?(Hash)
      return unavailable_prompt_compaction unless @agent_definition_version&.active_agent_connection.present?

      normalized = entry.deep_stringify_keys

      {
        "available" => true,
        "consultation_mode" => normalize_consultation_mode(normalized["consultation_mode"]),
        "workflow_execution" => normalize_workflow_execution(normalized["workflow_execution"]),
        "lifecycle" => normalized["lifecycle"].presence || "turn_scoped",
        "consultation_schema" => normalized["consultation_schema"].is_a?(Hash) ? normalized["consultation_schema"] : {},
        "artifact_schema" => normalized["artifact_schema"].is_a?(Hash) ? normalized["artifact_schema"] : {},
        "implementation_ref" => normalized["implementation_ref"],
      }.compact
    end

    def normalize_consultation_mode(value)
      candidate = value.to_s
      return candidate if SUPPORTED_CONSULTATION_MODES.include?(candidate)

      "none"
    end

    def normalize_workflow_execution(value)
      candidate = value.to_s
      return candidate if SUPPORTED_WORKFLOW_EXECUTION.include?(candidate)

      "unsupported"
    end

    def unavailable_prompt_compaction
      {
        "available" => false,
        "consultation_mode" => "none",
        "workflow_execution" => "unsupported",
      }
    end
  end
end
