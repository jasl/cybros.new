module Fenix
  module Runtime
    class ExecuteProgramTool
      def self.call(...)
        new(...).call
      end

      def initialize(payload:, collector: nil, control_client: nil, cancellation_probe: nil)
        @payload = payload.deep_stringify_keys
        @collector = collector
        @control_client = control_client
        @cancellation_probe = cancellation_probe
      end

      def call
        result = executor.call(
          tool_call: tool_call,
          tool_invocation: runtime_resource_refs["tool_invocation"] || @payload["tool_invocation"],
          command_run: runtime_resource_refs["command_run"] || @payload["command_run"],
          process_run: runtime_resource_refs["process_run"] || @payload["process_run"]
        )

        {
          "status" => "ok",
          "program_tool_call" => result.tool_call,
          "result" => result.tool_result,
          "output_chunks" => result.output_chunks,
          "summary_artifacts" => [],
        }
      rescue StandardError => error
        {
          "status" => "failed",
          "program_tool_call" => tool_call,
          "error" => Fenix::Runtime::ProgramToolExecutor.error_payload_for(error),
          "output_chunks" => executor_output_chunks,
          "summary_artifacts" => [],
        }
      end

      private

      def executor
        @executor ||= Fenix::Runtime::ProgramToolExecutor.new(
          context: execution_context,
          collector: @collector,
          control_client: @control_client,
          cancellation_probe: @cancellation_probe
        )
      end

      def execution_context
        @execution_context ||= begin
          workspace_root = Fenix::Workspace::Layout.default_root
          task = @payload.fetch("task").deep_stringify_keys
          capability_projection = @payload.fetch("capability_projection").deep_stringify_keys
          provider_context = @payload.fetch("provider_context").deep_stringify_keys
          runtime_context = @payload.fetch("runtime_context").deep_stringify_keys
          conversation_id = task.fetch("conversation_id")
          agent_context = normalized_agent_context(capability_projection:)
          runtime_identity = { "agent_program_version_id" => runtime_context.fetch("agent_program_version_id") }

          Fenix::Workspace::Bootstrap.call(
            workspace_root:,
            conversation_id:,
            agent_program_version_id: runtime_identity["agent_program_version_id"]
          )

          {
            "agent_task_run_id" => task["agent_task_run_id"],
            "workflow_node_id" => task.fetch("workflow_node_id"),
            "conversation_id" => conversation_id,
            "turn_id" => task["turn_id"],
            "logical_work_id" => runtime_context.fetch("logical_work_id"),
            "attempt_no" => runtime_context.fetch("attempt_no", 1).to_i,
            "agent_context" => agent_context,
            "capability_projection" => capability_projection,
            "provider_execution" => provider_context.fetch("provider_execution", {}).deep_stringify_keys,
            "model_context" => provider_context.fetch("model_context", {}).deep_stringify_keys,
            "runtime_identity" => runtime_identity,
            "workspace_context" => {
              "workspace_root" => workspace_root,
              "env_overlay" => Fenix::Workspace::EnvOverlay.call(
                workspace_root:,
                conversation_id:,
                agent_program_version_id: runtime_identity["agent_program_version_id"]
              ),
              "prompts" => Fenix::Prompts::Assembler.call(
                workspace_root:,
                conversation_id:,
                agent_program_version_id: runtime_identity["agent_program_version_id"],
                profile: agent_context.fetch("profile", "main"),
                is_subagent: agent_context.fetch("is_subagent", false)
              ),
            },
          }.compact
        end
      end

      def tool_call
        @tool_call ||= @payload.fetch("program_tool_call").deep_stringify_keys
      end

      def runtime_resource_refs
        @runtime_resource_refs ||= @payload.fetch("runtime_resource_refs", {}).deep_stringify_keys
      end

      def executor_output_chunks
        executor.instance_variable_get(:@collector).output_chunks.map(&:deep_stringify_keys)
      end

      def normalized_agent_context(capability_projection:)
        {
          "profile" => capability_projection["profile_key"] || "main",
          "is_subagent" => capability_projection["is_subagent"] == true,
          "subagent_session_id" => capability_projection["subagent_session_id"],
          "parent_subagent_session_id" => capability_projection["parent_subagent_session_id"],
          "subagent_depth" => capability_projection["subagent_depth"],
          "allowed_tool_names" => Array(capability_projection["tool_surface"]).filter_map { |entry| entry["tool_name"] },
          "owner_conversation_id" => capability_projection["owner_conversation_id"],
        }.compact
      end
    end
  end
end
