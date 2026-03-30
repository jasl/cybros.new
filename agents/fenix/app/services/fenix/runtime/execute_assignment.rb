require "securerandom"
require "open3"
require "timeout"

module Fenix
  module Runtime
    class ExecuteAssignment
      CancellationRequestedError = Class.new(StandardError)

      Result = Struct.new(:status, :reports, :trace, :output, :error, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, attempt: nil, on_report: nil, control_client: nil, cancellation_probe: nil)
        @context = Fenix::Context::BuildExecutionContext.call(mailbox_item: mailbox_item)
        @collector = Fenix::RuntimeSurface::ReportCollector.new(context: @context, on_report:)
        @attempt = attempt
        @control_client = control_client || Fenix::Runtime::ControlPlane.client
        @cancellation_probe = cancellation_probe
        @trace = []
        @current_tool_invocation = nil
      end

      def call
        return fail_unsupported_runtime_plane unless @context.fetch("runtime_plane") == "agent"

        check_canceled!
        @collector.started!

        prepared = Fenix::Hooks::PrepareTurn.call(context: @context)
        @trace << prepared.fetch("trace")
        check_canceled!

        compacted = Fenix::Hooks::CompactContext.call(
          messages: prepared.fetch("messages"),
          budget_hints: @context.fetch("budget_hints"),
          likely_model: prepared.fetch("likely_model")
        )
        @trace << compacted.fetch("trace")
        check_canceled!

        case @context.dig("task_payload", "mode")
        when "raise_error"
          raise StandardError, "boom"
        when "skills_catalog_list"
          execute_skill_flow(output: Fenix::Skills::CatalogList.call)
        when "skills_load"
          execute_skill_flow(
            output: Fenix::Skills::Load.call(
              skill_name: @context.dig("task_payload", "skill_name").to_s
            )
          )
        when "skills_read_file"
          execute_skill_flow(
            output: Fenix::Skills::ReadFile.call(
              skill_name: @context.dig("task_payload", "skill_name").to_s,
              relative_path: @context.dig("task_payload", "relative_path").to_s
            )
          )
        when "skills_install"
          execute_skill_flow(
            output: Fenix::Skills::Install.call(
              source_path: @context.dig("task_payload", "source_path").to_s
            )
          )
        else
          execute_deterministic_tool_flow
        end
      rescue CancellationRequestedError
        Result.new(
          status: "canceled",
          reports: @collector.reports,
          trace: @trace,
          error: {
            "failure_kind" => "canceled",
            "last_error_summary" => "execution canceled by agent task close request",
          }
        )
      rescue Fenix::Runtime::ExecutionTopology::UnsupportedActiveJobAdapterError => error
        fail_unsupported_execution_topology(error)
      rescue StandardError => error
        handled_error = Fenix::Hooks::HandleError.call(
          error: error,
          logical_work_id: @context.fetch("logical_work_id"),
          attempt_no: @context.fetch("attempt_no")
        )
        failed_invocation = failed_tool_invocation_payload(error)
        handled_error["tool_invocations"] = [failed_invocation] if failed_invocation.present?
        @trace << { "hook" => "handle_error", "error" => handled_error.fetch("last_error_summary") }
        @collector.fail!(terminal_payload: handled_error)

        Result.new(
          status: "failed",
          reports: @collector.reports,
          trace: @trace,
          error: handled_error
        )
      end

      private

      def execute_deterministic_tool_flow
        check_canceled!
        tool_call = build_deterministic_tool_call
        assert_execution_topology_supported!(tool_name: tool_call.fetch("tool_name"))
        return execute_process_tool_flow(tool_call) if process_tool?(tool_call.fetch("tool_name"))

        @current_tool_invocation = {
          "call_id" => tool_call.fetch("call_id"),
          "tool_name" => tool_call.fetch("tool_name"),
          "request_payload" => tool_call.except("call_id"),
        }
        reviewed_tool_call = Fenix::Hooks::ReviewToolCall.call(
          tool_call: tool_call,
          allowed_tool_names: @context.dig("agent_context", "allowed_tool_names")
        )
        @trace << { "hook" => "review_tool_call", "tool_name" => reviewed_tool_call.fetch("tool_name") }
        check_canceled!
        tool_invocation = provision_tool_invocation!(reviewed_tool_call)
        check_canceled!
        command_run = provision_command_run_if_needed!(reviewed_tool_call, tool_invocation)
        @current_tool_invocation = @current_tool_invocation.merge(build_current_tool_invocation(
          tool_call: reviewed_tool_call,
          tool_invocation: tool_invocation,
          command_run: command_run
        ))
        check_canceled!

        @collector.progress!(
          progress_payload: {
            "stage" => "tool_reviewed",
            "tool_invocation" => started_tool_invocation_payload(@current_tool_invocation),
          }
        )

        tool_result = execute_tool(
          reviewed_tool_call,
          tool_invocation: tool_invocation,
          command_run: command_run
        )
        projected_result = Fenix::Hooks::ProjectToolResult.call(
          tool_call: reviewed_tool_call,
          tool_result: tool_result
        )
        @trace << { "hook" => "project_tool_result", "content" => projected_result.fetch("content") }

        finalized_output = Fenix::Hooks::FinalizeOutput.call(
          projected_result: projected_result,
          context: @context
        )
        @trace << { "hook" => "finalize_output", "output" => finalized_output.fetch("output") }

        @collector.complete!(
          terminal_payload: {
            "output" => finalized_output.fetch("output"),
            "tool_invocations" => [
              completed_tool_invocation_payload(
                current_tool_invocation: @current_tool_invocation,
                response_payload: projected_result
              ),
            ],
          }
        )
        @current_tool_invocation = nil

        Result.new(
          status: "completed",
          reports: @collector.reports,
          trace: @trace,
          output: finalized_output.fetch("output")
        )
      end

      def execute_process_tool_flow(tool_call)
        check_canceled!
        reviewed_tool_call = Fenix::Hooks::ReviewToolCall.call(
          tool_call: tool_call,
          allowed_tool_names: @context.dig("agent_context", "allowed_tool_names")
        )
        @trace << { "hook" => "review_tool_call", "tool_name" => reviewed_tool_call.fetch("tool_name") }
        check_canceled!

        process_run = provision_process_run!(reviewed_tool_call)
        check_canceled! do
          report_process_canceled_before_start!(process_run_id: process_run.fetch("process_run_id"))
        end
        tool_result = execute_tool(
          reviewed_tool_call,
          tool_invocation: nil,
          command_run: nil,
          process_run: process_run
        )
        projected_result = Fenix::Hooks::ProjectToolResult.call(
          tool_call: reviewed_tool_call,
          tool_result: tool_result
        )
        @trace << { "hook" => "project_tool_result", "content" => projected_result.fetch("content") }

        finalized_output = Fenix::Hooks::FinalizeOutput.call(
          projected_result: projected_result,
          context: @context
        )
        @trace << { "hook" => "finalize_output", "output" => finalized_output.fetch("output") }

        @collector.complete!(terminal_payload: { "output" => finalized_output.fetch("output") })

        Result.new(
          status: "completed",
          reports: @collector.reports,
          trace: @trace,
          output: finalized_output.fetch("output")
        )
      end

      def execute_skill_flow(output:)
        check_canceled!
        @trace << { "hook" => "skills", "mode" => @context.dig("task_payload", "mode") }
        @collector.complete!(terminal_payload: { "output" => output })

        Result.new(
          status: "completed",
          reports: @collector.reports,
          trace: @trace,
          output: output
        )
      end

      def build_deterministic_tool_call
        tool_name = @context.dig("task_payload", "tool_name") || "calculator"
        arguments =
          case tool_name
          when "calculator"
            { "expression" => @context.dig("task_payload", "expression") || "2 + 2" }
          when "exec_command"
            {
              "command_line" => @context.dig("task_payload", "command_line") || "printf 'hello\\n'",
              "timeout_seconds" => @context.dig("task_payload", "timeout_seconds") || 30,
              "pty" => @context.dig("task_payload", "pty") || false,
            }
          when "write_stdin"
            {
              "command_run_id" => @context.dig("task_payload", "command_run_id"),
              "text" => @context.dig("task_payload", "text").to_s,
              "eof" => @context.dig("task_payload", "eof") || false,
              "wait_for_exit" => @context.dig("task_payload", "wait_for_exit") || false,
              "timeout_seconds" => @context.dig("task_payload", "timeout_seconds") || 30,
            }
          when "process_exec"
            {
              "command_line" => @context.dig("task_payload", "command_line") || "bin/dev",
              "kind" => @context.dig("task_payload", "kind") || "background_service",
            }
          when "workspace_read"
            {
              "path" => @context.dig("task_payload", "path") || "README.md",
            }
          when "workspace_write"
            {
              "path" => @context.dig("task_payload", "path") || "notes/output.txt",
              "content" => @context.dig("task_payload", "content").to_s,
            }
          when "memory_get"
            {
              "scope" => @context.dig("task_payload", "scope") || "all",
            }
          when "memory_search"
            {
              "query" => @context.dig("task_payload", "query").to_s,
              "limit" => @context.dig("task_payload", "limit") || 5,
            }
          when "memory_store"
            {
              "text" => @context.dig("task_payload", "text").to_s,
              "title" => @context.dig("task_payload", "title").to_s,
              "scope" => @context.dig("task_payload", "scope") || "daily",
            }
          else
            {}
          end

        {
          "call_id" => "tool-call-#{SecureRandom.uuid}",
          "tool_name" => tool_name,
          "arguments" => arguments,
        }
      end

      def execute_tool(tool_call, tool_invocation:, command_run:, process_run: nil)
        case tool_call.fetch("tool_name")
        when "calculator"
          evaluate_expression(tool_call.dig("arguments", "expression"))
        when "exec_command"
          execute_exec_command(
            tool_call: tool_call,
            tool_invocation: tool_invocation,
            command_run: command_run,
            command_line: tool_call.dig("arguments", "command_line"),
            timeout_seconds: tool_call.dig("arguments", "timeout_seconds"),
            pty: tool_call.dig("arguments", "pty")
          )
        when "write_stdin"
          execute_write_stdin(
            tool_call: tool_call,
            tool_invocation: tool_invocation,
            command_run_id: tool_call.dig("arguments", "command_run_id"),
            text: tool_call.dig("arguments", "text"),
            eof: tool_call.dig("arguments", "eof"),
            wait_for_exit: tool_call.dig("arguments", "wait_for_exit"),
            timeout_seconds: tool_call.dig("arguments", "timeout_seconds")
          )
        when "process_exec"
          execute_process_exec(
            process_run: process_run,
            command_line: tool_call.dig("arguments", "command_line")
          )
        when "workspace_read", "workspace_write"
          execute_workspace_tool(tool_call)
        when "memory_get", "memory_search", "memory_store"
          execute_memory_tool(tool_call)
        else
          raise ArgumentError, "unsupported deterministic tool #{tool_call.fetch("tool_name")}"
        end
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

      def execute_exec_command(tool_call:, tool_invocation:, command_run:, command_line:, timeout_seconds:, pty:)
        Fenix::Plugins::System::ExecCommand::Runtime.call(
          tool_call: tool_call.deep_dup,
          tool_invocation: tool_invocation.deep_dup,
          command_run: command_run.deep_dup,
          collector: @collector,
          control_client: @control_client,
          cancellation_probe: @cancellation_probe,
          current_agent_task_run_id:
        )
      end

      def execute_write_stdin(tool_call:, tool_invocation:, command_run_id:, text:, eof:, wait_for_exit:, timeout_seconds:)
        Fenix::Plugins::System::ExecCommand::Runtime.call(
          tool_call: tool_call.deep_dup,
          tool_invocation: tool_invocation.deep_dup,
          command_run: nil,
          collector: @collector,
          control_client: @control_client,
          cancellation_probe: @cancellation_probe,
          current_agent_task_run_id:
        )
      end

      def execute_process_exec(process_run:, command_line:)
        check_canceled! do
          report_process_canceled_before_start!(process_run_id: process_run.fetch("process_run_id"))
        end
        Fenix::Processes::Manager.spawn!(
          process_run_id: process_run.fetch("process_run_id"),
          command_line: command_line,
          control_client: @control_client
        )

        {
          "process_run_id" => process_run.fetch("process_run_id"),
          "lifecycle_state" => "running",
        }
      end

      def execute_workspace_tool(tool_call)
        Fenix::Plugins::System::Workspace::Runtime.call(
          tool_call: tool_call.deep_dup,
          workspace_root: @context.dig("workspace_context", "workspace_root")
        )
      end

      def execute_memory_tool(tool_call)
        Fenix::Plugins::System::Memory::Runtime.call(
          tool_call: tool_call.deep_dup,
          workspace_root: @context.dig("workspace_context", "workspace_root"),
          conversation_id: @context.fetch("conversation_id")
        )
      end

      def canceled?
        @cancellation_probe&.call == true
      end

      def check_canceled!(&block)
        return unless canceled?

        block&.call
        raise CancellationRequestedError, "execution canceled"
      end

      def report_process_canceled_before_start!(process_run_id:)
        @control_client.report!(
          payload: {
            "method_id" => "process_exited",
            "protocol_message_id" => "fenix-process-exited-#{SecureRandom.uuid}",
            "resource_type" => "ProcessRun",
            "resource_id" => process_run_id,
            "lifecycle_state" => "stopped",
            "metadata" => {
              "source" => "fenix_runtime",
              "reason" => "canceled_before_start",
            },
          }
        )
      end

      def current_agent_task_run_id
        @attempt&.agent_task_run_id || @context.fetch("agent_task_run_id")
      end

      def fail_unsupported_runtime_plane
        failure_payload = {
          "failure_kind" => "unsupported_runtime_plane",
          "last_error_summary" => "agent execution received #{@context.fetch("runtime_plane")} plane work",
          "retryable" => false,
        }
        @collector.fail!(terminal_payload: failure_payload)

        Result.new(
          status: "failed",
          reports: @collector.reports,
          trace: @trace,
          error: failure_payload
        )
      end

      def fail_unsupported_execution_topology(error)
        failure_payload = {
          "failure_kind" => "unsupported_execution_topology",
          "last_error_summary" => error.message,
          "retryable" => false,
          "active_job_adapter" => Fenix::Runtime::ExecutionTopology.queue_adapter_name,
        }
        @trace << { "hook" => "execution_topology", "error" => error.message }
        @collector.fail!(terminal_payload: failure_payload)

        Result.new(
          status: "failed",
          reports: @collector.reports,
          trace: @trace,
          error: failure_payload
        )
      end

      def failed_tool_invocation_payload(error)
        return if @current_tool_invocation.blank?

        {
          "event" => "failed",
          "call_id" => @current_tool_invocation.fetch("call_id"),
          "tool_name" => @current_tool_invocation.fetch("tool_name"),
          "request_payload" => @current_tool_invocation.fetch("request_payload"),
          "error_payload" => tool_invocation_error_payload(error),
        }.merge(
          {
            "tool_invocation_id" => @current_tool_invocation["tool_invocation_id"],
            "command_run_id" => @current_tool_invocation["command_run_id"],
          }.compact
        )
      end

      def provision_tool_invocation!(tool_call)
        @control_client.create_tool_invocation!(
          agent_task_run_id: current_agent_task_run_id,
          tool_name: tool_call.fetch("tool_name"),
          request_payload: tool_call.except("call_id"),
          idempotency_key: tool_call.fetch("call_id"),
          stream_output: streaming_tool?(tool_call.fetch("tool_name")),
          metadata: {
            "logical_work_id" => @context.fetch("logical_work_id"),
            "attempt_no" => @context.fetch("attempt_no"),
          }
        )
      end

      def provision_command_run_if_needed!(tool_call, tool_invocation)
        return unless tool_call.fetch("tool_name") == "exec_command"

        @control_client.create_command_run!(
          tool_invocation_id: tool_invocation.fetch("tool_invocation_id"),
          command_line: tool_call.dig("arguments", "command_line"),
          timeout_seconds: tool_call.dig("arguments", "timeout_seconds"),
          pty: tool_call.dig("arguments", "pty"),
          metadata: {
            "logical_work_id" => @context.fetch("logical_work_id"),
            "attempt_no" => @context.fetch("attempt_no"),
          }
        )
      end

      def build_current_tool_invocation(tool_call:, tool_invocation:, command_run:)
        {
          "tool_invocation_id" => tool_invocation.fetch("tool_invocation_id"),
          "command_run_id" => command_run&.fetch("command_run_id"),
          "call_id" => tool_call.fetch("call_id"),
          "tool_name" => tool_call.fetch("tool_name"),
          "request_payload" => tool_call.except("call_id"),
        }.compact
      end

      def started_tool_invocation_payload(current_tool_invocation)
        {
          "event" => "started",
          "tool_invocation_id" => current_tool_invocation.fetch("tool_invocation_id"),
          "command_run_id" => current_tool_invocation["command_run_id"],
          "call_id" => current_tool_invocation.fetch("call_id"),
          "tool_name" => current_tool_invocation.fetch("tool_name"),
          "request_payload" => current_tool_invocation.fetch("request_payload"),
        }.compact
      end

      def completed_tool_invocation_payload(current_tool_invocation:, response_payload:)
        {
          "event" => "completed",
          "tool_invocation_id" => current_tool_invocation.fetch("tool_invocation_id"),
          "command_run_id" => current_tool_invocation["command_run_id"],
          "call_id" => current_tool_invocation.fetch("call_id"),
          "tool_name" => current_tool_invocation.fetch("tool_name"),
          "response_payload" => response_payload,
        }.compact
      end

      def streaming_tool?(tool_name)
        %w[exec_command write_stdin].include?(tool_name)
      end

      def process_tool?(tool_name)
        tool_name == "process_exec"
      end

      def assert_execution_topology_supported!(tool_name:)
        return unless registry_backed_tool?(tool_name)

        Fenix::Runtime::ExecutionTopology.assert_registry_backed_execution_supported!(tool_name:)
      end

      def registry_backed_tool?(tool_name)
        process_tool?(tool_name) || %w[exec_command write_stdin].include?(tool_name)
      end

      def provision_process_run!(tool_call)
        @control_client.create_process_run!(
          agent_task_run_id: current_agent_task_run_id,
          tool_name: tool_call.fetch("tool_name"),
          kind: tool_call.dig("arguments", "kind"),
          command_line: tool_call.dig("arguments", "command_line"),
          idempotency_key: tool_call.fetch("call_id"),
          metadata: {
            "logical_work_id" => @context.fetch("logical_work_id"),
            "attempt_no" => @context.fetch("attempt_no"),
          }
        )
      end

      def tool_invocation_error_payload(error)
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
          Fenix::Plugins::System::Memory::Runtime::ValidationError
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
    end
  end
end
