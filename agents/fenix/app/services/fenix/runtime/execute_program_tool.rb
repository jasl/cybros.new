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
          tool_invocation: @payload["tool_invocation"],
          command_run: @payload["command_run"],
          process_run: @payload["process_run"]
        )

        {
          "status" => "completed",
          "tool_call" => result.tool_call,
          "result" => result.tool_result,
          "output_chunks" => result.output_chunks,
          "summary" => summarize_result(result.tool_result),
        }
      rescue StandardError => error
        {
          "status" => "failed",
          "tool_call" => tool_call,
          "error" => Fenix::Runtime::ProgramToolExecutor.error_payload_for(error),
          "output_chunks" => executor_output_chunks,
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
          conversation_id = @payload.fetch("conversation_id")
          agent_context = @payload.fetch("agent_context", {}).deep_stringify_keys
          runtime_identity = @payload.fetch("runtime_identity", {}).deep_stringify_keys

          Fenix::Workspace::Bootstrap.call(
            workspace_root:,
            conversation_id:,
            deployment_public_id: runtime_identity["deployment_public_id"]
          )

          {
            "agent_task_run_id" => @payload["agent_task_run_id"],
            "workflow_node_id" => @payload.fetch("workflow_node_id"),
            "conversation_id" => conversation_id,
            "turn_id" => @payload.fetch("turn_id"),
            "logical_work_id" => @payload["logical_work_id"] || "workflow-node:#{@payload.fetch("workflow_node_id")}",
            "attempt_no" => @payload.fetch("attempt_no", 1).to_i,
            "agent_context" => agent_context,
            "provider_execution" => @payload.fetch("provider_execution", {}).deep_stringify_keys,
            "model_context" => @payload.fetch("model_context", {}).deep_stringify_keys,
            "runtime_identity" => runtime_identity,
            "workspace_context" => {
              "workspace_root" => workspace_root,
              "env_overlay" => Fenix::Workspace::EnvOverlay.call(
                workspace_root:,
                conversation_id:,
                deployment_public_id: runtime_identity["deployment_public_id"]
              ),
              "prompts" => Fenix::Prompts::Assembler.call(
                workspace_root:,
                conversation_id:,
                deployment_public_id: runtime_identity["deployment_public_id"],
                profile: agent_context.fetch("profile", "main"),
                is_subagent: agent_context.fetch("is_subagent", false)
              ),
            },
          }.compact
        end
      end

      def tool_call
        @tool_call ||= {
          "call_id" => @payload.fetch("tool_call_id"),
          "tool_name" => @payload.fetch("tool_name"),
          "arguments" => @payload.fetch("arguments", {}).deep_stringify_keys,
        }
      end

      def executor_output_chunks
        executor.instance_variable_get(:@collector).output_chunks.map(&:deep_stringify_keys)
      end

      def summarize_result(result)
        case result
        when String, Numeric, TrueClass, FalseClass
          result.to_s
        else
          result.to_json
        end
      end
    end
  end
end
