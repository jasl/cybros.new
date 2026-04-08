module Fenix
  module Runtime
    class ProgramToolExecutor
      Result = Struct.new(:tool_call, :tool_result, :output_chunks, keyword_init: true)

      class ProgressCollector
        attr_reader :output_chunks

        def initialize(delegate: nil)
          @delegate = delegate
          @output_chunks = []
        end

        def progress!(progress_payload:)
          normalized_payload = progress_payload.deep_stringify_keys
          tool_output = normalized_payload["tool_invocation_output"]
          @output_chunks.concat(Array(tool_output&.fetch("output_chunks", []))) if tool_output.present?
          @delegate&.progress!(progress_payload:)
        end
      end

      class NullControlClient
        def activate_command_run!(command_run_id:)
          {
            "method_id" => "command_run_activate",
            "result" => "activated",
            "command_run_id" => command_run_id,
          }
        end

        def report!(payload:)
          payload
        end
      end

      def self.call(...)
        new(...).call
      end

      def self.error_payload_for(error)
        case error
        when Fenix::Hooks::ReviewToolCall::ToolNotVisibleError
          {
            "classification" => "authorization",
            "code" => "tool_not_allowed",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Hooks::ReviewToolCall::UnsupportedToolError
          {
            "classification" => "semantic",
            "code" => "unsupported_tool",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Plugins::System::Workspace::Runtime::ValidationError,
          Fenix::Plugins::System::Memory::Runtime::ValidationError,
          Fenix::Plugins::System::Web::Runtime::ValidationError,
          Fenix::Plugins::System::Browser::Runtime::ValidationError,
          Fenix::Plugins::System::Process::Runtime::ValidationError
          {
            "classification" => "semantic",
            "code" => "validation_error",
            "message" => error.message,
            "retryable" => false,
          }
        else
          {
            "classification" => "runtime",
            "code" => "runtime_error",
            "message" => error.message,
            "retryable" => false,
          }
        end
      end

      def initialize(context:, collector: nil, control_client: nil, cancellation_probe: nil)
        @context = context.deep_stringify_keys
        @collector = ProgressCollector.new(delegate: collector)
        @control_client = control_client || NullControlClient.new
        @cancellation_probe = cancellation_probe
      end

      def call(tool_call:, tool_invocation: nil, command_run: nil, process_run: nil)
        reviewed_tool_call = Fenix::Hooks::ReviewToolCall.call(
          tool_call: tool_call.deep_stringify_keys,
          allowed_tool_names: @context.dig("agent_context", "allowed_tool_names")
        )

        execute(
          tool_call: reviewed_tool_call,
          tool_invocation: tool_invocation,
          command_run: command_run,
          process_run: process_run
        )
      end

      def assert_execution_topology_supported!(tool_name:)
        return unless registry_backed_tool?(tool_name)

        Fenix::Runtime::ExecutionTopology.assert_registry_backed_execution_supported!(tool_name:)
      end

      public :assert_execution_topology_supported!

      def execute(tool_call:, tool_invocation: nil, command_run: nil, process_run: nil)
        normalized_tool_call = tool_call.deep_stringify_keys
        assert_execution_topology_supported!(tool_name: normalized_tool_call.fetch("tool_name"))
        tool_registry_entry = Fenix::Runtime::SystemToolRegistry.fetch!(normalized_tool_call.fetch("tool_name"))
        tool_result = tool_registry_entry.fetch(:executor).call(
          tool_call: normalized_tool_call,
          context: @context,
          collector: @collector,
          control_client: @control_client,
          cancellation_probe: @cancellation_probe,
          current_execution_owner_id: current_execution_owner_id,
          tool_invocation: tool_invocation,
          command_run: command_run,
          process_run: process_run
        )

        Result.new(
          tool_call: normalized_tool_call,
          tool_result:,
          output_chunks: @collector.output_chunks.map(&:deep_stringify_keys)
        )
      end

      private

      def current_execution_owner_id
        @context["agent_task_run_id"].presence ||
          @context["turn_id"].presence ||
          @context.fetch("workflow_node_id")
      end

      def registry_backed_tool?(tool_name)
        Fenix::Runtime::ExecutionTopology.registry_backed_tool_name?(tool_name)
      end
    end
  end
end
