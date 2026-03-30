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
        return start_command_run_session(command_run_id: command_run.fetch("command_run_id"), timeout_seconds:, command_line:) if pty

        execute_one_shot_command(
          tool_call: tool_call,
          tool_invocation_id: tool_invocation.fetch("tool_invocation_id"),
          command_run_id: command_run.fetch("command_run_id"),
          command_line: command_line,
          timeout_seconds: timeout_seconds,
          timeout_label: tool_call.fetch("tool_name")
        )
      end

      def execute_write_stdin(tool_call:, tool_invocation:, command_run_id:, text:, eof:, wait_for_exit:, timeout_seconds:)
        check_canceled!
        command_run = Fenix::Runtime::CommandRunRegistry.lookup(command_run_id:)
        raise ArgumentError, "unknown command run #{command_run_id}" if command_run.blank?
        raise ArgumentError, "command run #{command_run_id} is not owned by this agent task" unless command_run.agent_task_run_id == current_agent_task_run_id

        stdin_bytes = text.to_s.bytesize
        command_run.stdin.write(text.to_s) if text.present?
        command_run.stdin.flush if text.present?
        command_run.stdin.close if eof && !command_run.stdin.closed?

        output_chunks = []
        output_chunks.concat(drain_attached_output(command_run:, wait_for_exit:, timeout_seconds:))
        emit_tool_output!(
          tool_call: tool_call,
          tool_invocation_id: tool_invocation.fetch("tool_invocation_id"),
          command_run_id: command_run_id,
          output_chunks:
        ) if output_chunks.any?

        response_payload = {
          "command_run_id" => command_run_id,
          "stdin_bytes" => stdin_bytes,
          "session_closed" => wait_for_exit,
          "output_streamed" => command_run.stdout_bytes.positive? || command_run.stderr_bytes.positive?,
          "stdout_bytes" => command_run.stdout_bytes,
          "stderr_bytes" => command_run.stderr_bytes,
        }
        if wait_for_exit
          response_payload["exit_status"] = command_run.wait_thread.value.exitstatus
        end

        response_payload
      ensure
        Fenix::Runtime::CommandRunRegistry.release(command_run_id:) if wait_for_exit && command_run_id.present?
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

      def execute_one_shot_command(tool_call:, tool_invocation_id:, command_run_id:, command_line:, timeout_seconds:, timeout_label:)
        check_canceled!
        stdout = +""
        stderr = +""
        exit_status = nil
        process_pid = nil

        Open3.popen3("/bin/sh", "-lc", command_line.to_s) do |stdin, command_stdout, command_stderr, wait_thr|
          Fenix::Runtime::CommandRunRegistry.register(
            command_run_id: command_run_id,
            agent_task_run_id: current_agent_task_run_id,
            stdin: stdin,
            stdout: command_stdout,
            stderr: command_stderr,
            wait_thread: wait_thr
          )
          process_pid = wait_thr.pid
          activate_command_run!(command_run_id)
          stdin.close

          deadline_at = monotonic_now + timeout_seconds.to_i
          readers = {
            command_stdout => { stream: "stdout", buffer: stdout },
            command_stderr => { stream: "stderr", buffer: stderr },
          }

          until readers.empty?
            check_canceled!
            remaining = deadline_at - monotonic_now
            raise Timeout::Error, "#{timeout_label} timed out after #{timeout_seconds} seconds" if remaining <= 0

            ready =
              begin
                IO.select(readers.keys, nil, nil, [remaining, 0.1].min)
              rescue IOError, Errno::EBADF
                readers.delete_if { |io, _| io.closed? rescue true }
                nil
              end
            next if ready.blank?

            ready.first.each do |io|
              begin
                chunk = io.read_nonblock(4096)
                next if chunk.blank?

                stream_details = readers.fetch(io)
                stream_details.fetch(:buffer) << chunk
                emit_tool_output!(
                  tool_call: tool_call,
                  tool_invocation_id: tool_invocation_id,
                  command_run_id: command_run_id,
                  output_chunks: [{ "stream" => stream_details.fetch(:stream), "text" => chunk }]
                )
              rescue IO::WaitReadable
                nil
              rescue EOFError, IOError, Errno::EIO
                readers.delete(io)
              end
            end
          end

          exit_status = wait_thr.value.exitstatus
        end

        {
          "command_run_id" => command_run_id,
          "exit_status" => exit_status,
          "stdout" => stdout,
          "stderr" => stderr,
          "stdout_bytes" => stdout.bytesize,
          "stderr_bytes" => stderr.bytesize,
          "output_streamed" => stdout.present? || stderr.present?,
        }
      rescue Timeout::Error
        terminate_subprocess!(pid: process_pid)
        raise
      ensure
        Fenix::Runtime::CommandRunRegistry.release(command_run_id:) if command_run_id.present?
      end

      def start_command_run_session(command_run_id:, command_line:, timeout_seconds:)
        check_canceled!
        stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", command_line.to_s)
        Fenix::Runtime::CommandRunRegistry.register(
          command_run_id: command_run_id,
          agent_task_run_id: current_agent_task_run_id,
          stdin: stdin,
          stdout: stdout,
          stderr: stderr,
          wait_thread: wait_thread
        )
        activate_command_run!(command_run_id)

        {
          "command_run_id" => command_run_id,
          "attached" => true,
          "session_closed" => false,
          "timeout_seconds" => timeout_seconds.to_i,
        }
      end

      def drain_attached_output(command_run:, wait_for_exit:, timeout_seconds:)
        chunks = []
        deadline_at = monotonic_now + timeout_seconds.to_i

        loop do
          check_canceled!
          chunks.concat(read_available_output(command_run:, timeout_seconds: 0.05))
          break unless wait_for_exit
          break unless command_run.wait_thread.alive?
          raise Timeout::Error, "write_stdin timed out after #{timeout_seconds} seconds" if monotonic_now >= deadline_at
        end

        chunks.concat(read_available_output(command_run:, timeout_seconds: 0.05))
        chunks
      end

      def read_available_output(command_run:, timeout_seconds:)
        readers = {}
        readers[command_run.stdout] = "stdout" unless command_run.stdout.closed?
        readers[command_run.stderr] = "stderr" unless command_run.stderr.closed?
        return [] if readers.empty?

        ready = IO.select(readers.keys, nil, nil, timeout_seconds)
        return [] if ready.blank?

        output_chunks = []

        ready.first.each do |io|
          begin
            chunk = io.read_nonblock(4096)
            next if chunk.blank?

            stream = readers.fetch(io)
            if stream == "stdout"
              command_run.stdout_bytes += chunk.bytesize
            else
              command_run.stderr_bytes += chunk.bytesize
            end
            output_chunks << { "stream" => stream, "text" => chunk }
          rescue IO::WaitReadable
            nil
          rescue EOFError
            nil
          end
        end

        output_chunks
      end

      def emit_tool_output!(tool_call:, tool_invocation_id:, output_chunks:, command_run_id: nil)
        return if canceled?

        @collector.progress!(
          progress_payload: {
            "stage" => "tool_output",
            "tool_invocation_output" => {
              "tool_invocation_id" => tool_invocation_id,
              "call_id" => tool_call.fetch("call_id"),
              "tool_name" => tool_call.fetch("tool_name"),
              "command_run_id" => command_run_id,
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

      def activate_command_run!(command_run_id)
        return if command_run_id.blank?

        @control_client.activate_command_run!(command_run_id: command_run_id)
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
