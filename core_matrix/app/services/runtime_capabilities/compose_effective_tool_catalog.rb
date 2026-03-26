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
      ordinary_entries = {}
      ordinary_order = []
      reserved_entries = {}
      reserved_order = []

      source_catalogs.each do |catalog|
        catalog.each do |entry|
          normalized_entry = normalize_entry(entry)
          tool_name = normalized_entry.fetch("tool_name")

          if reserved_core_matrix_tool?(tool_name)
            next if reserved_entries.key?(tool_name)

            reserved_entries[tool_name] = normalized_entry
            reserved_order << tool_name
            next
          end

          next if ordinary_entries.key?(tool_name)

          ordinary_entries[tool_name] = normalized_entry
          ordinary_order << tool_name
        end
      end

      reserved_order.map { |tool_name| reserved_entries.fetch(tool_name) } +
        ordinary_order.map { |tool_name| ordinary_entries.fetch(tool_name) }
    end

    private

    def source_catalogs
      [
        @execution_environment&.tool_catalog,
        @capability_snapshot&.tool_catalog,
        @core_matrix_tool_catalog,
      ].map { |catalog| Array(catalog) }
    end

    def normalize_entry(entry)
      entry.deep_stringify_keys
    end

    def reserved_core_matrix_tool?(tool_name)
      tool_name.start_with?("core_matrix__")
    end
  end
end
