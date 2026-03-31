module ProviderExecution
  class BuildToolExecutionBatch
    def self.call(...)
      new(...).call
    end

    def initialize(workflow_node:, tool_calls:, round_bindings:)
      @workflow_node = workflow_node
      @tool_calls = Array(tool_calls).map { |entry| entry.deep_stringify_keys }
      @round_bindings = Array(round_bindings)
    end

    def call
      {
        "batch_id" => batch_id,
        "provider_round_index" => current_round_index,
        "stages" => normalized_stages,
        "ordered_tool_node_keys" => ordered_tool_node_keys,
        "successor" => {
          "node_key" => successor_node_key,
          "node_type" => "turn_step",
          "metadata" => {
            "provider_round_index" => current_round_index + 1,
            "prior_tool_node_keys" => cumulative_prior_tool_node_keys,
            "resume_batch_id" => batch_id,
            "yielding_node_key" => @workflow_node.node_key,
          },
        },
      }
    end

    private

    def batch_id
      @batch_id ||= "provider_tool_batch:#{@workflow_node.public_id}:round:#{current_round_index}"
    end

    def current_round_index
      @current_round_index ||= begin
        value = @workflow_node.metadata["provider_round_index"]
        value.present? ? value.to_i : 1
      end
    end

    def ordered_tool_node_keys
      @ordered_tool_node_keys ||= tool_entries.map { |entry| entry.fetch("tool_node_key") }
    end

    def cumulative_prior_tool_node_keys
      @cumulative_prior_tool_node_keys ||= Array(@workflow_node.metadata["prior_tool_node_keys"]) + ordered_tool_node_keys
    end

    def successor_node_key
      @successor_node_key ||= "provider_round_#{current_round_index + 1}"
    end

    def tool_entries
      @tool_entries ||= @tool_calls.each_with_index.map do |tool_call, index|
        binding = @round_bindings.find { |candidate| candidate.tool_definition.tool_name == tool_call.fetch("tool_name") } ||
          raise(ActiveRecord::RecordNotFound, "Couldn't find ToolBinding for #{tool_call.fetch("tool_name")}")

        {
          "tool_call" => tool_call,
          "tool_node_key" => "provider_round_#{current_round_index}_tool_#{index + 1}",
          "source_tool_binding_id" => binding.id,
          "parallel_safe" => binding.binding_payload.dig("execution_policy", "parallel_safe") == true,
        }
      end
    end

    def normalized_stages
      @normalized_stages ||= begin
        packed = []

        tool_entries.each do |entry|
          if entry.fetch("parallel_safe")
            if packed.last&.fetch("mode") == "parallel_safe_group"
              packed.last.fetch("entries") << entry
            else
              packed << {
                "mode" => "parallel_safe_group",
                "entries" => [entry],
              }
            end
          else
            packed << {
              "mode" => "serial_group",
              "entries" => [entry],
            }
          end
        end

        packed.each_with_index.map do |stage, stage_index|
          entries = stage.fetch("entries")

          {
            "stage_index" => stage_index,
            "dispatch_mode" => entries.length > 1 ? "parallel" : "serial",
            "completion_barrier" => "wait_all",
            "join_node_key" => "provider_round_#{current_round_index}_join_#{stage_index + 1}",
            "tool_entries" => entries.each_with_index.map do |entry, entry_index|
              entry.merge(
                "stage_index" => stage_index,
                "stage_position" => entry_index
              )
            end,
          }
        end
      end
    end
  end
end
