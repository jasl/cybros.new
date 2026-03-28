module RuntimeCapabilities
  class ComposeEffectiveToolCatalog
    RESERVED_SUBAGENT_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

    CORE_MATRIX_TOOL_CATALOG = RESERVED_SUBAGENT_TOOL_NAMES.map do |tool_name|
      {
        "tool_name" => tool_name,
        "tool_kind" => "effect_intent",
        "implementation_source" => "core_matrix",
        "implementation_ref" => "core_matrix/#{tool_name}",
        "input_schema" => { "type" => "object", "properties" => {} },
        "result_schema" => { "type" => "object", "properties" => {} },
        "streaming_support" => false,
        "idempotency_policy" => "best_effort",
      }
    end.freeze

    def self.call(...)
      new(...).call
    end

    def initialize(execution_environment:, capability_snapshot:, core_matrix_tool_catalog: CORE_MATRIX_TOOL_CATALOG)
      @execution_environment = execution_environment
      @capability_snapshot = capability_snapshot
      @core_matrix_tool_catalog = Array(core_matrix_tool_catalog)
    end

    def call
      RuntimeCapabilityContract.build(
        execution_environment: @execution_environment,
        capability_snapshot: @capability_snapshot,
        core_matrix_tool_catalog: @core_matrix_tool_catalog
      ).effective_tool_catalog
    end
  end
end
