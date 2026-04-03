require "securerandom"

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

        tool_result =
          case normalized_tool_call.fetch("tool_name")
          when "calculator"
            evaluate_expression(normalized_tool_call.dig("arguments", "expression"))
          when "command_run_list", "command_run_read_output", "command_run_terminate", "command_run_wait", "exec_command", "write_stdin"
            Fenix::Plugins::System::ExecCommand::Runtime.call(
              tool_call: normalized_tool_call,
              tool_invocation: normalize_tool_invocation(tool_invocation, normalized_tool_call),
              command_run: normalize_command_run(command_run, normalized_tool_call),
              workspace_root: @context.dig("workspace_context", "workspace_root"),
              collector: @collector,
              control_client: @control_client,
              cancellation_probe: @cancellation_probe,
              current_agent_task_run_id: current_execution_owner_id
            )
          when "process_exec", "process_list", "process_proxy_info", "process_read_output"
            Fenix::Plugins::System::Process::Runtime.call(
              tool_call: normalized_tool_call,
              process_run: normalize_process_run(process_run, normalized_tool_call),
              control_client: @control_client,
              current_agent_task_run_id: current_execution_owner_id
            )
          when "browser_list", "browser_open", "browser_session_info", "browser_navigate", "browser_get_content", "browser_screenshot", "browser_close"
            Fenix::Plugins::System::Browser::Runtime.call(
              tool_call: normalized_tool_call,
              current_agent_task_run_id: current_execution_owner_id
            )
          when "workspace_find", "workspace_read", "workspace_stat", "workspace_tree", "workspace_write"
            Fenix::Plugins::System::Workspace::Runtime.call(
              tool_call: normalized_tool_call,
              workspace_root: @context.dig("workspace_context", "workspace_root")
            )
          when "memory_append_daily", "memory_compact_summary", "memory_get", "memory_list", "memory_search", "memory_store"
            Fenix::Plugins::System::Memory::Runtime.call(
              tool_call: normalized_tool_call,
              workspace_root: @context.dig("workspace_context", "workspace_root"),
              conversation_id: @context.fetch("conversation_id"),
              agent_program_version_id: @context.dig("runtime_identity", "agent_program_version_id")
            )
          when "web_fetch", "web_search", "firecrawl_search", "firecrawl_scrape"
            Fenix::Plugins::System::Web::Runtime.call(tool_call: normalized_tool_call)
          else
            raise ArgumentError, "unsupported deterministic tool #{normalized_tool_call.fetch("tool_name")}"
          end

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

      def normalize_tool_invocation(tool_invocation, tool_call)
        tool_invocation&.deep_stringify_keys || {
          "tool_invocation_id" => "tool-invocation-#{tool_call.fetch("call_id", SecureRandom.uuid)}",
        }
      end

      def normalize_command_run(command_run, tool_call)
        return command_run&.deep_stringify_keys unless tool_call.fetch("tool_name") == "exec_command"

        command_run&.deep_stringify_keys || {
          "command_run_id" => "command-run-#{tool_call.fetch("call_id", SecureRandom.uuid)}",
        }
      end

      def normalize_process_run(process_run, tool_call)
        return process_run&.deep_stringify_keys unless tool_call.fetch("tool_name") == "process_exec"

        process_run&.deep_stringify_keys || {
          "process_run_id" => "process-run-#{tool_call.fetch("call_id", SecureRandom.uuid)}",
          "agent_task_run_id" => current_execution_owner_id,
        }
      end

      def evaluate_expression(expression)
        left, operator, right = expression.to_s.strip.split(/\s+/, 3)
        left_value = Integer(left)
        right_value = Integer(right)

        case operator
        when "+"
          left_value + right_value
        when "-"
          left_value - right_value
        else
          raise ArgumentError, "unsupported calculator operator #{operator}"
        end
      end

      def process_tool?(tool_name)
        tool_name == "process_exec"
      end

      def registry_backed_tool?(tool_name)
        Fenix::Runtime::ExecutionTopology.registry_backed_tool_name?(tool_name)
      end

      def assert_execution_topology_supported!(tool_name:)
        return unless registry_backed_tool?(tool_name)

        Fenix::Runtime::ExecutionTopology.assert_registry_backed_execution_supported!(tool_name:)
      end
    end
  end
end
