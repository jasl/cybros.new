module ToolBindings
  class FreezeForWorkflowNode
    RESERVED_TOOL_NAMES = RuntimeCapabilities::ComposeEffectiveToolCatalog::RESERVED_SUBAGENT_TOOL_NAMES

    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_catalog: nil)
      @workflow_node = workflow_node
      @tool_catalog_provided = !tool_catalog.nil?
      @tool_catalog = Array(tool_catalog).map { |entry| entry.deep_stringify_keys }
    end

    def call
      ToolBindings::ProjectCapabilitySnapshot.call(
        capability_snapshot: capability_snapshot,
        execution_environment: execution_environment
      )

      if @tool_catalog_provided
        requested_tool_catalog.each do |tool_entry|
          definition = upsert_definition_for_entry!(tool_entry)
          implementation = upsert_implementation_for_entry!(definition, tool_entry)
          upsert_binding!(definition:, implementation:, round_scoped: true)
        end

        return workflow_node_bindings
          .joins(:tool_definition)
          .where(tool_definitions: { tool_name: requested_tool_names })
      end

      allowed_tool_names.each do |tool_name|
        definition = definitions_by_name.fetch(tool_name) do
          raise_invalid!("missing governed tool definition for #{tool_name}")
        end
        implementation = ToolBindings::SelectImplementation.call(tool_definition: definition)
        upsert_binding!(definition:, implementation:, round_scoped: false)
      end

      workflow_node_bindings.where(tool_definition: definitions_by_name.values)
    end

    private

    def workflow_node_bindings
      @workflow_node.tool_bindings.where(agent_task_run_id: nil)
    end

    def capability_snapshot
      @capability_snapshot ||= turn_record.pinned_capability_snapshot || turn_record.agent_deployment.active_capability_snapshot || raise_invalid!("missing capability snapshot")
    end

    def execution_environment
      @execution_environment ||= @workflow_node.conversation.execution_environment
    end

    def requested_tool_catalog
      @requested_tool_catalog ||= @tool_catalog.uniq { |entry| entry.fetch("tool_name") }.tap do |catalog|
        catalog.each { |entry| validate_round_tool_entry!(entry) }
      end
    end

    def requested_tool_names
      @requested_tool_names ||= requested_tool_catalog.map { |entry| entry.fetch("tool_name") }
    end

    def allowed_tool_names
      @allowed_tool_names ||= begin
        profile_allowed_names = Array(
          capability_snapshot.profile_catalog.fetch(current_profile_key, {}).fetch("allowed_tool_names", [])
        ).uniq
        if profile_allowed_names.present?
          profile_allowed_names
        else
          Array(turn_record.execution_snapshot.agent_context.fetch("allowed_tool_names", [])).uniq
        end
      end
    end

    def turn_record
      @turn_record ||= @workflow_node.turn
    end

    def current_profile_key
      turn_record.execution_snapshot.agent_context.fetch("profile", "main")
    end

    def definitions_by_name
      @definitions_by_name ||= ToolDefinition.where(
        capability_snapshot: capability_snapshot,
        tool_name: allowed_tool_names
      ).includes(:tool_implementations).index_by(&:tool_name)
    end

    def upsert_definition_for_entry!(tool_entry)
      definition = ToolDefinition.find_or_initialize_by(
        capability_snapshot: capability_snapshot,
        tool_name: tool_entry.fetch("tool_name")
      )
      definition.installation = @workflow_node.installation
      definition.tool_kind = tool_entry.fetch("tool_kind")
      definition.governance_mode = governance_mode_for(tool_entry)
      definition.policy_payload = {
        "default_implementation_ref" => tool_entry.fetch("implementation_ref"),
        "default_implementation_source" => tool_entry.fetch("implementation_source"),
        "round_scoped" => true,
      }
      definition.save! if definition.new_record? || definition.changed?
      definition
    end

    def upsert_implementation_for_entry!(definition, tool_entry)
      implementation_source = find_or_create_source!(tool_entry)
      definition.tool_implementations.where.not(
        implementation_ref: tool_entry.fetch("implementation_ref")
      ).update_all(default_for_snapshot: false)

      implementation = definition.tool_implementations.find_or_initialize_by(
        implementation_ref: tool_entry.fetch("implementation_ref")
      )
      implementation.installation = @workflow_node.installation
      implementation.implementation_source = implementation_source
      implementation.input_schema = tool_entry.fetch("input_schema", {})
      implementation.result_schema = tool_entry.fetch("result_schema", {})
      implementation.streaming_support = tool_entry.fetch("streaming_support", false)
      implementation.idempotency_policy = tool_entry.fetch("idempotency_policy")
      implementation.default_for_snapshot = true
      implementation.metadata = implementation_metadata_for(tool_entry)
      implementation.save! if implementation.new_record? || implementation.changed?
      implementation
    end

    def upsert_binding!(definition:, implementation:, round_scoped:)
      binding = ToolBinding.find_or_initialize_by(
        workflow_node: @workflow_node,
        agent_task_run: nil,
        tool_definition: definition
      )
      binding.installation = @workflow_node.installation
      binding.tool_implementation = implementation
      binding.binding_reason = "snapshot_default"
      binding.binding_payload = {
        "capability_snapshot_id" => capability_snapshot.id,
        "capability_snapshot_version" => capability_snapshot.version,
        "governance_mode" => definition.governance_mode,
        "round_scoped" => round_scoped,
        "execution_policy" => execution_policy_for(definition: definition, implementation: implementation),
      }
      binding.save! if binding.new_record? || binding.changed?
      binding
    end

    def governance_mode_for(tool_entry)
      tool_name = tool_entry.fetch("tool_name")
      source = tool_entry.fetch("implementation_source")

      return "reserved" if reserved_tool_name?(tool_name)
      return "whitelist_only" if source == "execution_environment"

      "replaceable"
    end

    def validate_round_tool_entry!(tool_entry)
      tool_name = tool_entry.fetch("tool_name")
      return unless reserved_tool_name?(tool_name) || tool_entry.fetch("implementation_source") == "core_matrix"

      raise_invalid!("round tool catalog must not override reserved core matrix tool #{tool_name}")
    end

    def reserved_tool_name?(tool_name)
      tool_name.start_with?(CapabilitySnapshot::RESERVED_CORE_MATRIX_PREFIX) || RESERVED_TOOL_NAMES.include?(tool_name)
    end

    def find_or_create_source!(tool_entry)
      source_kind = tool_entry.fetch("implementation_source")
      source_ref = case source_kind
      when "execution_environment"
        execution_environment.public_id
      when "agent", "kernel"
        "capability_snapshot:#{capability_snapshot.id}"
      when "core_matrix"
        "built_in"
      else
        tool_entry.fetch("implementation_ref")
      end

      ImplementationSource.find_or_create_by!(
        installation: @workflow_node.installation,
        source_kind: source_kind,
        source_ref: source_ref
      ) do |source|
        source.metadata = {}
      end
    end

    def implementation_metadata_for(tool_entry)
      tool_entry.deep_dup.except(
        "tool_name",
        "tool_kind",
        "implementation_ref",
        "input_schema",
        "result_schema",
        "streaming_support",
        "idempotency_policy"
      ).merge(
        "execution_policy" => execution_policy_for(tool_entry: tool_entry)
      )
    end

    def raise_invalid!(message)
      @workflow_node.errors.add(:base, message)
      raise ActiveRecord::RecordInvalid, @workflow_node
    end

    def execution_policy_for(definition: nil, implementation: nil, tool_entry: nil)
      policy =
        if tool_entry.present?
          tool_entry["execution_policy"]
        else
          implementation&.metadata&.dig("execution_policy") ||
            definition&.policy_payload&.dig("execution_policy")
        end

      policy = policy.deep_stringify_keys if policy.is_a?(Hash)

      {
        "parallel_safe" => policy&.fetch("parallel_safe", false) || false,
      }
    end
  end
end
