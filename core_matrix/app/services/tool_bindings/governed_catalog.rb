module ToolBindings
  class GovernedCatalog
    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, execution_runtime:, core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG)
      @agent_definition_version = agent_definition_version
      @execution_runtime = execution_runtime
      @core_matrix_tool_catalog = core_matrix_tool_catalog
    end

    def call
      ToolBindings::ProjectCapabilitySnapshot.call(
        agent_definition_version: @agent_definition_version,
        execution_runtime: @execution_runtime,
        core_matrix_tool_catalog: @core_matrix_tool_catalog
      )

      projected_entries.map do |entry|
        definition = definitions_by_name.fetch(entry.fetch("tool_name"))
        entry.merge(
          "tool_definition_id" => definition.public_id,
          "tool_implementation_id" => definition.default_implementation.public_id,
          "governance_mode" => definition.governance_mode
        )
      end
    end

    private

    def projected_entries
      @projected_entries ||= begin
        entries = RuntimeCapabilityContract.build(
          execution_runtime: @execution_runtime,
          agent_definition_version: @agent_definition_version,
          core_matrix_tool_catalog: @core_matrix_tool_catalog
        ).effective_tool_catalog

        allowed_names = @agent_definition_version.profile_policy.values.flat_map { |profile| Array(profile["allowed_tool_names"]) }.uniq
        if allowed_names.blank?
          entries
        else
          entries.select { |entry| allowed_names.include?(entry.fetch("tool_name")) }
        end
      end
    end

    def definitions_by_name
      @definitions_by_name ||= ToolDefinition.where(
        agent_definition_version: @agent_definition_version,
        tool_name: projected_entries.map { |entry| entry.fetch("tool_name") }
      ).includes(:tool_implementations).index_by(&:tool_name)
    end
  end
end
