module ToolBindings
  class ProjectCapabilitySnapshot
    RESERVED_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

    def self.call(...)
      new(...).call
    end

    def initialize(agent_definition_version:, execution_runtime:, core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG)
      @agent_definition_version = agent_definition_version
      @execution_runtime = execution_runtime
      @core_matrix_tool_catalog = Array(core_matrix_tool_catalog)
    end

    def call
      ApplicationRecord.transaction do
        projectable_catalog.each do |effective_entry|
          definition = upsert_definition!(effective_entry)
          synchronize_implementations!(definition, candidates_for(effective_entry.fetch("tool_name")), effective_entry)
        end
      end

      @agent_definition_version.tool_definitions.includes(:tool_implementations)
    end

    private

    def projectable_catalog
      @projectable_catalog ||= begin
        allowed_names = profile_allowed_tool_names
        catalog = effective_tool_catalog
        if allowed_names.blank?
          catalog
        else
          catalog.select { |entry| allowed_names.include?(entry.fetch("tool_name")) }
        end
      end
    end

    def effective_tool_catalog
      @effective_tool_catalog ||= RuntimeCapabilityContract.build(
        execution_runtime: @execution_runtime,
        agent_definition_version: @agent_definition_version,
        core_matrix_tool_catalog: @core_matrix_tool_catalog
      ).effective_tool_catalog
    end

    def profile_allowed_tool_names
      @profile_allowed_tool_names ||= @agent_definition_version.profile_catalog.values.flat_map do |profile|
        Array(profile["allowed_tool_names"])
      end.uniq
    end

    def candidates_for(tool_name)
      [@core_matrix_tool_catalog, @execution_runtime&.tool_catalog, @agent_definition_version.tool_catalog]
        .flat_map { |catalog| Array(catalog) }
        .select { |entry| entry.fetch("tool_name") == tool_name }
    end

    def upsert_definition!(effective_entry)
      definition = ToolDefinition.create_or_find_by!(
        agent_definition_version: @agent_definition_version,
        tool_name: effective_entry.fetch("tool_name")
      ) do |record|
        record.installation = installation
        record.tool_kind = effective_entry.fetch("tool_kind")
        record.governance_mode = governance_mode_for(effective_entry)
        record.policy_payload = definition_policy_payload_for(effective_entry)
      end

      definition.assign_attributes(
        installation: installation,
        tool_kind: effective_entry.fetch("tool_kind"),
        governance_mode: governance_mode_for(effective_entry),
        policy_payload: definition_policy_payload_for(effective_entry)
      )
      definition.save! if definition.changed?
      definition
    end

    def definition_policy_payload_for(effective_entry)
      {
        "default_implementation_ref" => effective_entry.fetch("implementation_ref"),
        "default_implementation_source" => effective_entry.fetch("implementation_source"),
        "execution_policy" => execution_policy_for(effective_entry),
      }
    end

    def synchronize_implementations!(definition, candidates, effective_entry)
      target_ref = effective_entry.fetch("implementation_ref")

      definition.tool_implementations.where.not(implementation_ref: candidates.map { |entry| entry.fetch("implementation_ref") }).update_all(default_for_snapshot: false)

      candidates.each do |candidate|
        implementation_source = find_or_create_source!(candidate)
        implementation = definition.tool_implementations.create_or_find_by!(
          implementation_ref: candidate.fetch("implementation_ref")
        ) do |record|
          record.installation = installation
          record.implementation_source = implementation_source
          record.input_schema = candidate.fetch("input_schema", {})
          record.result_schema = candidate.fetch("result_schema", {})
          record.streaming_support = candidate.fetch("streaming_support", false)
          record.idempotency_policy = candidate.fetch("idempotency_policy")
          record.default_for_snapshot = false
          record.metadata = implementation_metadata_for(candidate)
        end
        implementation.assign_attributes(
          installation: installation,
          implementation_source: implementation_source,
          input_schema: candidate.fetch("input_schema", {}),
          result_schema: candidate.fetch("result_schema", {}),
          streaming_support: candidate.fetch("streaming_support", false),
          idempotency_policy: candidate.fetch("idempotency_policy"),
          default_for_snapshot: false,
          metadata: implementation_metadata_for(candidate)
        )
        implementation.save! if implementation.changed?
      end

      definition.tool_implementations.where.not(implementation_ref: target_ref).where(default_for_snapshot: true).update_all(default_for_snapshot: false)
      definition.tool_implementations.where(implementation_ref: target_ref).update_all(default_for_snapshot: true)
    end

    def find_or_create_source!(candidate)
      source_kind, source_ref = source_identity_for(candidate)

      ImplementationSource.find_or_create_by!(
        installation: installation,
        source_kind: source_kind,
        source_ref: source_ref
      ) do |source|
        source.metadata = {}
      end
    end

    def source_identity_for(candidate)
      source_kind = candidate.fetch("implementation_source")

      source_ref = case source_kind
      when "execution_runtime"
        @execution_runtime.public_id
      when "agent", "kernel"
        "agent_definition_version:#{@agent_definition_version.public_id}"
      when "core_matrix"
        "built_in"
      else
        candidate.fetch("implementation_ref")
      end

      [source_kind, source_ref]
    end

    def governance_mode_for(effective_entry)
      tool_name = effective_entry.fetch("tool_name")
      source = effective_entry.fetch("implementation_source")

      return "reserved" if reserved_tool_name?(tool_name)
      return "whitelist_only" if source == "execution_runtime"

      "replaceable"
    end

    def reserved_tool_name?(tool_name)
      tool_name.start_with?(AgentDefinitionVersion::RESERVED_CORE_MATRIX_PREFIX) || RESERVED_TOOL_NAMES.include?(tool_name)
    end

    def implementation_metadata_for(candidate)
      candidate.deep_dup.except(
        "tool_name",
        "tool_kind",
        "implementation_ref",
        "input_schema",
        "result_schema",
        "streaming_support",
        "idempotency_policy"
      ).merge(
        "execution_policy" => execution_policy_for(candidate)
      )
    end

    def installation
      @installation ||= @agent_definition_version.installation
    end

    def execution_policy_for(entry)
      policy = entry["execution_policy"]
      policy = policy.deep_stringify_keys if policy.is_a?(Hash)

      {
        "parallel_safe" => policy&.fetch("parallel_safe", false) || false,
      }
    end
  end
end
