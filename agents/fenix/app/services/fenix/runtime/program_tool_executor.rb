module Fenix
  module Runtime
    class ProgramToolExecutor
      Result = Struct.new(:tool_call, :tool_result, :output_chunks, keyword_init: true)
      UnsupportedToolError = Class.new(StandardError)
      ToolNotAllowedError = Class.new(UnsupportedToolError)

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
          @delegate&.progress!(progress_payload: progress_payload)
        end
      end

      class NullControlClient
        def report!(payload:)
          payload
        end
      end

      def self.call(...)
        new(...).call
      end

      def self.error_payload_for(error)
        case error
        when ToolNotAllowedError
          {
            "classification" => "authorization",
            "code" => "tool_not_allowed",
            "message" => error.message,
            "retryable" => false,
          }
        when UnsupportedToolError
          {
            "classification" => "semantic",
            "code" => "unsupported_tool",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Runtime::ToolExecutors::ExecCommand::ValidationError
          {
            "classification" => "semantic",
            "code" => "validation_error",
            "message" => error.message,
            "retryable" => false,
          }
        when Fenix::Browser::SessionManager::ValidationError
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
        execute(
          tool_call: validate_tool_call!(tool_call),
          tool_invocation: tool_invocation,
          command_run: command_run,
          process_run: process_run
        )
      end

      def execute(tool_call:, tool_invocation: nil, command_run: nil, process_run: nil)
        normalized_tool_call = tool_call.deep_stringify_keys
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
          tool_result: tool_result,
          output_chunks: @collector.output_chunks.map(&:deep_stringify_keys)
        )
      end

      private

      def validate_tool_call!(tool_call)
        tool_call = tool_call.deep_stringify_keys
        tool_name = tool_call.fetch("tool_name")
        raise UnsupportedToolError, "unsupported tool #{tool_name}" unless Fenix::Runtime::SystemToolRegistry.supported_tool_names.include?(tool_name)
        unless Array(@context.dig("agent_context", "allowed_tool_names")).map(&:to_s).include?(tool_name)
          raise ToolNotAllowedError, "tool #{tool_name} is not visible for this assignment"
        end

        tool_call
      end

      def current_execution_owner_id
        @context["agent_task_run_id"].presence ||
          @context["turn_id"].presence ||
          @context.fetch("workflow_node_id")
      end
    end
  end
end
