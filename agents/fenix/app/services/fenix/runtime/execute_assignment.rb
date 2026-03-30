require "securerandom"
require "open3"
require "timeout"

module Fenix
  module Runtime
    class ExecuteAssignment
      Result = Struct.new(:status, :reports, :trace, :output, :error, keyword_init: true)

      def self.call(...)
        new(...).call
      end

      def initialize(mailbox_item:, attempt: nil, on_report: nil)
        @context = Fenix::Context::BuildExecutionContext.call(mailbox_item: mailbox_item)
        @collector = Fenix::RuntimeSurface::ReportCollector.new(context: @context, on_report:)
        @attempt = attempt
        @trace = []
        @current_tool_invocation = nil
      end

      def call
        return fail_unsupported_runtime_plane unless @context.fetch("runtime_plane") == "agent"

        @collector.started!

        prepared = Fenix::Hooks::PrepareTurn.call(context: @context)
        @trace << prepared.fetch("trace")

        compacted = Fenix::Hooks::CompactContext.call(
          messages: prepared.fetch("messages"),
          budget_hints: @context.fetch("budget_hints"),
          likely_model: prepared.fetch("likely_model")
        )
        @trace << compacted.fetch("trace")

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
        tool_call = build_deterministic_tool_call
        @current_tool_invocation = tool_call.deep_dup
        reviewed_tool_call = Fenix::Hooks::ReviewToolCall.call(
          tool_call: tool_call,
          allowed_tool_names: @context.dig("agent_context", "allowed_tool_names")
        )
        @trace << { "hook" => "review_tool_call", "tool_name" => reviewed_tool_call.fetch("tool_name") }

        @collector.progress!(
          progress_payload: {
            "stage" => "tool_reviewed",
            "tool_invocation" => {
              "event" => "started",
              "call_id" => reviewed_tool_call.fetch("call_id"),
              "tool_name" => reviewed_tool_call.fetch("tool_name"),
              "request_payload" => reviewed_tool_call.except("call_id"),
            },
          }
        )

        tool_result = execute_tool(reviewed_tool_call)
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
              {
                "event" => "completed",
                "call_id" => reviewed_tool_call.fetch("call_id"),
                "tool_name" => reviewed_tool_call.fetch("tool_name"),
                "response_payload" => projected_result,
              },
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

      def execute_skill_flow(output:)
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
          when "shell_exec"
            {
              "command_line" => @context.dig("task_payload", "command_line") || "printf 'hello\\n'",
              "timeout_seconds" => @context.dig("task_payload", "timeout_seconds") || 30,
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

      def execute_tool(tool_call)
        case tool_call.fetch("tool_name")
        when "calculator"
          evaluate_expression(tool_call.dig("arguments", "expression"))
        when "shell_exec"
          execute_shell_command(
            tool_call: tool_call,
            command_line: tool_call.dig("arguments", "command_line"),
            timeout_seconds: tool_call.dig("arguments", "timeout_seconds")
          )
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

      def execute_shell_command(tool_call:, command_line:, timeout_seconds:)
        stdout = +""
        stderr = +""
        exit_status = nil
        process_pid = nil

        Open3.popen3("/bin/sh", "-lc", command_line.to_s) do |stdin, command_stdout, command_stderr, wait_thr|
          process_pid = wait_thr.pid
          stdin.close

          deadline_at = monotonic_now + timeout_seconds.to_i
          readers = {
            command_stdout => { stream: "stdout", buffer: stdout },
            command_stderr => { stream: "stderr", buffer: stderr },
          }

          until readers.empty?
            remaining = deadline_at - monotonic_now
            raise Timeout::Error, "shell_exec timed out after #{timeout_seconds} seconds" if remaining <= 0

            ready = IO.select(readers.keys, nil, nil, [remaining, 0.1].min)
            next if ready.blank?

            ready.first.each do |io|
              begin
                chunk = io.read_nonblock(4096)
                next if chunk.blank?

                stream_details = readers.fetch(io)
                stream_details.fetch(:buffer) << chunk
                emit_tool_output!(tool_call:, output_chunks: [{ "stream" => stream_details.fetch(:stream), "text" => chunk }])
              rescue IO::WaitReadable
                nil
              rescue EOFError
                readers.delete(io)
              end
            end
          end

          exit_status = wait_thr.value.exitstatus
        end

        {
          "exit_status" => exit_status,
          "stdout" => stdout,
          "stderr" => stderr,
        }
      rescue Timeout::Error
        terminate_subprocess!(pid: process_pid)
        raise
      end

      def emit_tool_output!(tool_call:, output_chunks:)
        @collector.progress!(
          progress_payload: {
            "stage" => "tool_output",
            "tool_invocation_output" => {
              "call_id" => tool_call.fetch("call_id"),
              "tool_name" => tool_call.fetch("tool_name"),
              "output_chunks" => output_chunks,
            },
          }
        )
      end

      def terminate_subprocess!(pid:)
        return if pid.blank?

        Process.kill("TERM", pid)
        sleep(0.1)
        Process.kill("KILL", pid)
      rescue Errno::ESRCH
        nil
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
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

      def failed_tool_invocation_payload(error)
        return if @current_tool_invocation.blank?

        {
          "event" => "failed",
          "call_id" => @current_tool_invocation.fetch("call_id"),
          "tool_name" => @current_tool_invocation.fetch("tool_name"),
          "request_payload" => @current_tool_invocation.except("call_id"),
          "error_payload" => tool_invocation_error_payload(error),
        }
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
