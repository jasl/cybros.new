module Fenix
  module Runtime
    class ExecuteProgramTool
      UnsupportedToolError = Class.new(StandardError)
      ToolNotAllowedError = Class.new(UnsupportedToolError)

      def self.call(...)
        new(...).call
      end

      def initialize(payload:)
        @payload = payload.deep_stringify_keys
      end

      def call
        validate_visibility!
        execution = execute_tool

        {
          "status" => "ok",
          "program_tool_call" => tool_call,
          "result" => execution.fetch("result"),
          "output_chunks" => execution.fetch("output_chunks"),
          "summary_artifacts" => execution.fetch("summary_artifacts"),
        }
      rescue StandardError => error
        {
          "status" => "failed",
          "program_tool_call" => tool_call,
          "failure" => error_payload_for(error),
          "output_chunks" => [],
          "summary_artifacts" => [],
        }
      end

      private

      def execute_tool
        case tool_call.fetch("tool_name")
        when "compact_context"
          {
            "result" => Fenix::Hooks::CompactContext.call(
              messages: tool_call.dig("arguments", "messages") || [],
              budget_hints: tool_call.dig("arguments", "budget_hints") || {},
              likely_model: payload_context.dig("provider_context", "model_context", "model_slug")
            ),
            "output_chunks" => [],
            "summary_artifacts" => [],
          }
        when *Fenix::Runtime::SystemToolRegistry.supported_tool_names
          execution = Fenix::Runtime::ProgramToolExecutor.new(context: payload_context).call(
            tool_call: tool_call,
            command_run: runtime_resource_refs["command_run"],
            process_run: runtime_resource_refs["process_run"]
          )

          {
            "result" => execution.tool_result,
            "output_chunks" => execution.output_chunks,
            "summary_artifacts" => [],
          }
        else
          raise UnsupportedToolError, "unsupported program tool #{tool_call.fetch("tool_name")}"
        end
      end

      def validate_visibility!
        return if allowed_tool_names.include?(tool_call.fetch("tool_name"))

        raise ToolNotAllowedError, "tool #{tool_call.fetch("tool_name")} is not visible for this assignment"
      end

      def allowed_tool_names
        Array(payload_context.dig("agent_context", "allowed_tool_names")).map(&:to_s)
      end

      def payload_context
        @payload_context ||= Fenix::Runtime::PayloadContext.call(payload: @payload)
      end

      def runtime_resource_refs
        @runtime_resource_refs ||= @payload.fetch("runtime_resource_refs", {}).deep_stringify_keys
      end

      def tool_call
        @tool_call ||= @payload.fetch("program_tool_call").deep_stringify_keys
      end

      def error_payload_for(error)
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
        else
          {
            "classification" => "runtime",
            "code" => "runtime_error",
            "message" => error.message,
            "retryable" => false,
          }
        end
      end
    end
  end
end
