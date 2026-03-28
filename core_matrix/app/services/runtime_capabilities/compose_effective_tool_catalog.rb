module RuntimeCapabilities
  class ComposeEffectiveToolCatalog
    CORE_MATRIX_TOOL_CATALOG = [].freeze

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
