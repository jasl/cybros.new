module ToolBindings
  class ProjectCapabilitySnapshot
    RESERVED_TOOL_NAMES = RuntimeCapabilityContract::RESERVED_SUBAGENT_TOOL_NAMES

    def self.call(...)
      new(...).call
    end

    def initialize(capability_snapshot:, execution_environment:, core_matrix_tool_catalog: RuntimeCapabilities::ComposeEffectiveToolCatalog::CORE_MATRIX_TOOL_CATALOG)
      @capability_snapshot = capability_snapshot
      @execution_environment = execution_environment
      @core_matrix_tool_catalog = Array(core_matrix_tool_catalog)
    end

    def call
      ApplicationRecord.transaction do
        projectable_catalog.each do |effective_entry|
          definition = upsert_definition!(effective_entry)
          synchronize_implementations!(definition, candidates_for(effective_entry.fetch("tool_name")), effective_entry)
        end
      end

      @capability_snapshot.tool_definitions.includes(:tool_implementations)
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
        execution_environment: @execution_environment,
        capability_snapshot: @capability_snapshot,
        core_matrix_tool_catalog: @core_matrix_tool_catalog
      ).effective_tool_catalog
    end

    def profile_allowed_tool_names
      @profile_allowed_tool_names ||= @capability_snapshot.profile_catalog.values.flat_map do |profile|
        Array(profile["allowed_tool_names"])
      end.uniq
    end

    def candidates_for(tool_name)
      [@core_matrix_tool_catalog, @execution_environment.tool_catalog, @capability_snapshot.tool_catalog]
        .flat_map { |catalog| Array(catalog) }
        .select { |entry| entry.fetch("tool_name") == tool_name }
    end

    def upsert_definition!(effective_entry)
      definition = ToolDefinition.find_or_initialize_by(
        capability_snapshot: @capability_snapshot,
        tool_name: effective_entry.fetch("tool_name")
      )
      definition.installation = installation
      definition.tool_kind = effective_entry.fetch("tool_kind")
      definition.governance_mode = governance_mode_for(effective_entry)
      definition.policy_payload = {
        "default_implementation_ref" => effective_entry.fetch("implementation_ref"),
        "default_implementation_source" => effective_entry.fetch("implementation_source"),
        "execution_policy" => execution_policy_for(effective_entry),
      }
      definition.save! if definition.new_record? || definition.changed?
      definition
    end

    def synchronize_implementations!(definition, candidates, effective_entry)
      target_ref = effective_entry.fetch("implementation_ref")

      definition.tool_implementations.where.not(implementation_ref: candidates.map { |entry| entry.fetch("implementation_ref") }).update_all(default_for_snapshot: false)

      candidates.each do |candidate|
        implementation_source = find_or_create_source!(candidate)
        implementation = definition.tool_implementations.find_or_initialize_by(
          implementation_ref: candidate.fetch("implementation_ref")
        )
        implementation.installation = installation
        implementation.implementation_source = implementation_source
        implementation.input_schema = candidate.fetch("input_schema", {})
        implementation.result_schema = candidate.fetch("result_schema", {})
        implementation.streaming_support = candidate.fetch("streaming_support", false)
        implementation.idempotency_policy = candidate.fetch("idempotency_policy")
        implementation.default_for_snapshot = false
        implementation.metadata = implementation_metadata_for(candidate)
        implementation.save! if implementation.new_record? || implementation.changed?
      end

      default_implementation = definition.tool_implementations.find_by!(implementation_ref: target_ref)
      default_implementation.update!(default_for_snapshot: true) unless default_implementation.default_for_snapshot?
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
      when "execution_environment"
        @execution_environment.public_id
      when "agent", "kernel"
        "capability_snapshot:#{@capability_snapshot.id}"
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
      return "whitelist_only" if source == "execution_environment"

      "replaceable"
    end

    def reserved_tool_name?(tool_name)
      tool_name.start_with?(CapabilitySnapshot::RESERVED_CORE_MATRIX_PREFIX) || RESERVED_TOOL_NAMES.include?(tool_name)
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
      @installation ||= @capability_snapshot.agent_deployment.installation
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
