module ToolBindings
  class FreezeForTask
    def self.call(...)
      new(...).call
    end

    def initialize(agent_task_run:)
      @agent_task_run = agent_task_run
    end

    def call
      return @agent_task_run.tool_bindings if @agent_task_run.tool_bindings.exists?

      ToolBindings::ProjectCapabilitySnapshot.call(
        agent_definition_version: agent_definition_version,
        execution_runtime: execution_runtime
      )

      allowed_tool_names.each do |tool_name|
        definition = definitions_by_name.fetch(tool_name) do
          raise_invalid!("missing governed tool definition for #{tool_name}")
        end
        implementation = ToolBindings::SelectImplementation.call(tool_definition: definition)

        binding = ToolBinding.find_or_initialize_by(
          agent_task_run: @agent_task_run,
          tool_definition: definition
        )
        binding.installation = @agent_task_run.installation
        binding.workflow_node ||= @agent_task_run.workflow_node
        binding.tool_implementation = implementation
        binding.binding_reason = "snapshot_default"
        binding.round_scoped = false
        binding.parallel_safe = execution_policy_for(definition:, implementation:)
        binding.runtime_state ||= {}
        binding.save!
      end

      @agent_task_run.tool_bindings
    end

    private

    def agent_definition_version
      @agent_definition_version ||= turn_record.agent_definition_version || raise_invalid!("missing agent definition version")
    end

    def execution_runtime
      @execution_runtime ||= @agent_task_run.turn.execution_runtime
    end

    def allowed_tool_names
      @allowed_tool_names ||= begin
        profile_allowed_names = Array(
          agent_definition_version.profile_policy.fetch(current_profile_key, {}).fetch("allowed_tool_names", [])
        ).uniq
        if profile_allowed_names.present?
          profile_allowed_names
        else
          Array(turn_record.execution_snapshot.capability_projection.fetch("tool_surface", [])).map { |entry| entry.fetch("tool_name") }.uniq
        end
      end
    end

    def turn_record
      @turn_record ||= Turn.find(@agent_task_run.turn_id)
    end

    def current_profile_key
      turn_record.execution_snapshot.capability_projection.fetch("profile_key", "main")
    end

    def definitions_by_name
      @definitions_by_name ||= ToolDefinition.where(
        agent_definition_version: agent_definition_version,
        tool_name: allowed_tool_names
      ).includes(:tool_implementations).index_by(&:tool_name)
    end

    def execution_policy_for(definition:, implementation:)
      implementation&.metadata&.dig("execution_policy", "parallel_safe") ||
        definition&.policy_payload&.dig("execution_policy", "parallel_safe") ||
        false
    end

    def raise_invalid!(message)
      @agent_task_run.errors.add(:base, message)
      raise ActiveRecord::RecordInvalid, @agent_task_run
    end
  end
end
