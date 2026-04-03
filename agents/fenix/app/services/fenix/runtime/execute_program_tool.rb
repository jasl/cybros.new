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
        @execution_context ||= Fenix::Runtime::PayloadContext.call(payload: @payload)
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
    end
  end
end
