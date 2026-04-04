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
        return fail_unsupported_runtime_plane unless @context.fetch("runtime_plane") == "program"

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

        dispatch = Fenix::Runtime::Assignments::DispatchMode.call(
          task_payload: @context.fetch("task_payload", {})
        )

        case dispatch.fetch("kind")
        when "raise_error"
          raise StandardError, "boom"
        when "skill_flow"
          execute_skill_flow(output: dispatch.fetch("output"))
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
        program_tool_executor.send(:assert_execution_topology_supported!, tool_name: tool_call.fetch("tool_name"))
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
        program_tool_executor.send(:assert_execution_topology_supported!, tool_name: reviewed_tool_call.fetch("tool_name"))
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
        Fenix::Runtime::Assignments::BuildToolCall.call(
          task_payload: @context.fetch("task_payload", {})
        )
      end

      def execute_tool(tool_call, tool_invocation:, command_run:, process_run: nil)
        program_tool_executor.execute(
          tool_call:,
          tool_invocation:,
          command_run:,
          process_run:
        ).tool_result
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
          "last_error_summary" => "program execution received #{@context.fetch("runtime_plane")} plane work",
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
            "proxy" => {
              "target_port" => tool_call.dig("arguments", "proxy_port"),
            }.compact.presence,
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

      def provision_process_run!(tool_call)
        @control_client.create_process_run!(
          agent_task_run_id: current_agent_task_run_id,
          tool_name: tool_call.fetch("tool_name"),
          kind: normalize_process_kind(tool_call.dig("arguments", "kind")),
          command_line: tool_call.dig("arguments", "command_line"),
          idempotency_key: tool_call.fetch("call_id"),
          metadata: {
            "logical_work_id" => @context.fetch("logical_work_id"),
            "attempt_no" => @context.fetch("attempt_no"),
            "proxy" => {
              "target_port" => tool_call.dig("arguments", "proxy_port"),
            }.compact.presence,
          }
        )
      end

      def normalize_process_kind(kind)
        case kind.to_s
        when "", "background", "background_service", "command", "process", "web", "web_server", "server", "default"
          "background_service"
        else
          kind
        end
      end

      def tool_invocation_error_payload(error)
        Fenix::Runtime::ProgramToolExecutor.error_payload_for(error)
      end

      def program_tool_executor
        @program_tool_executor ||= Fenix::Runtime::ProgramToolExecutor.new(
          context: @context,
          collector: @collector,
          control_client: @control_client,
          cancellation_probe: @cancellation_probe
        )
      end
    end
  end
end
