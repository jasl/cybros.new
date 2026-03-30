require "open3"

module Fenix
  module Plugins
    module System
      module ExecCommand
        class Runtime
          class CancellationRequestedError < StandardError; end

          def self.call(...)
            new(...).call
          end

          def initialize(tool_call:, tool_invocation:, command_run:, collector:, control_client:, cancellation_probe:, current_agent_task_run_id:)
            @tool_call = tool_call
            @tool_invocation = tool_invocation
            @command_run = command_run
            @collector = collector
            @control_client = control_client
            @cancellation_probe = cancellation_probe
            @current_agent_task_run_id = current_agent_task_run_id
          end

          def call
            case @tool_call.fetch("tool_name")
            when "command_run_list"
              execute_command_run_list
            when "command_run_read_output"
              execute_command_run_read_output
            when "command_run_terminate"
              execute_command_run_terminate
            when "command_run_wait"
              execute_command_run_wait
            when "exec_command"
              execute_exec_command
            when "write_stdin"
              execute_write_stdin
            else
              raise ArgumentError, "unsupported exec command runtime tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          def execute_command_run_list
            {
              "entries" => Fenix::Runtime::CommandRunRegistry.list(agent_task_run_id: @current_agent_task_run_id),
            }
          end

          def execute_command_run_read_output
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id")
            command_run = lookup_owned_command_run!(command_run_id)

            output_chunks = read_available_output(command_run:, timeout_seconds: 0.05, command_run_id:)
            emit_tool_output!(command_run_id:, output_chunks:) if output_chunks.any?

            snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id:)
            raise ArgumentError, "unknown command run #{command_run_id}" if snapshot.blank?

            snapshot.merge("session_closed" => false)
          end

          def execute_command_run_terminate
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id")
            lookup_owned_command_run!(command_run_id)

            snapshot = Fenix::Runtime::CommandRunRegistry.terminate(command_run_id:)
            raise ArgumentError, "unknown command run #{command_run_id}" if snapshot.blank?

            snapshot
          end

          def execute_command_run_wait
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id")
            timeout_seconds = @tool_call.dig("arguments", "timeout_seconds") || 30
            command_run = lookup_owned_command_run!(command_run_id)

            output_chunks = drain_attached_output(
              command_run:,
              wait_for_exit: true,
              timeout_seconds:
            )
            emit_tool_output!(command_run_id:, output_chunks:) if output_chunks.any?

            snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id:)
            exit_status = command_run.wait_thread.value.exitstatus

            snapshot&.merge(
              "session_closed" => true,
              "exit_status" => exit_status,
              "output_streamed" => snapshot.fetch("stdout_bytes").positive? || snapshot.fetch("stderr_bytes").positive?
            ) || {
              "command_run_id" => command_run_id,
              "session_closed" => true,
              "exit_status" => exit_status,
              "output_streamed" => false,
              "stdout_bytes" => 0,
              "stderr_bytes" => 0,
              "stdout_tail" => "",
              "stderr_tail" => "",
            }
          ensure
            Fenix::Runtime::CommandRunRegistry.release(command_run_id:) if command_run_id.present?
          end

          def execute_exec_command
            return start_command_run_session if @tool_call.dig("arguments", "pty")

            execute_one_shot_command(
              command_line: @tool_call.dig("arguments", "command_line"),
              timeout_seconds: @tool_call.dig("arguments", "timeout_seconds"),
              timeout_label: @tool_call.fetch("tool_name")
            )
          end

          def execute_write_stdin
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id")
            command_run = Fenix::Runtime::CommandRunRegistry.lookup(command_run_id:)
            raise ArgumentError, "unknown command run #{command_run_id}" if command_run.blank?
            raise ArgumentError, "command run #{command_run_id} is not owned by this agent task" unless command_run.agent_task_run_id == @current_agent_task_run_id

            text = @tool_call.dig("arguments", "text").to_s
            wait_for_exit = @tool_call.dig("arguments", "wait_for_exit")
            timeout_seconds = @tool_call.dig("arguments", "timeout_seconds")
            stdin_bytes = text.bytesize

            command_run.stdin.write(text) if text.present?
            command_run.stdin.flush if text.present?
            command_run.stdin.close if @tool_call.dig("arguments", "eof") && !command_run.stdin.closed?

            output_chunks = drain_attached_output(
              command_run:,
              wait_for_exit:,
              timeout_seconds:
            )
            emit_tool_output!(command_run_id:, output_chunks:) if output_chunks.any?

            snapshot = Fenix::Runtime::CommandRunRegistry.output_snapshot(command_run_id:) || {
              "stdout_bytes" => command_run.stdout_bytes,
              "stderr_bytes" => command_run.stderr_bytes,
              "stdout_tail" => "",
              "stderr_tail" => "",
            }

            response_payload = {
              "command_run_id" => command_run_id,
              "stdin_bytes" => stdin_bytes,
              "session_closed" => wait_for_exit,
              "output_streamed" => snapshot.fetch("stdout_bytes").positive? || snapshot.fetch("stderr_bytes").positive?,
              "stdout_bytes" => snapshot.fetch("stdout_bytes"),
              "stderr_bytes" => snapshot.fetch("stderr_bytes"),
              "stdout_tail" => snapshot.fetch("stdout_tail"),
              "stderr_tail" => snapshot.fetch("stderr_tail"),
            }
            response_payload["exit_status"] = command_run.wait_thread.value.exitstatus if wait_for_exit
            response_payload
          ensure
            Fenix::Runtime::CommandRunRegistry.release(command_run_id:) if wait_for_exit && command_run_id.present?
          end

          def execute_one_shot_command(command_line:, timeout_seconds:, timeout_label:)
            check_canceled!
            stdout = +""
            stderr = +""
            exit_status = nil
            process_pid = nil
            command_run_id = @command_run.fetch("command_run_id")

            Open3.popen3("/bin/sh", "-lc", command_line.to_s) do |stdin, command_stdout, command_stderr, wait_thr|
              Fenix::Runtime::CommandRunRegistry.register(
                command_run_id:,
                agent_task_run_id: @current_agent_task_run_id,
                stdin:,
                stdout: command_stdout,
                stderr: command_stderr,
                wait_thread: wait_thr
              )
              process_pid = wait_thr.pid
              activate_registered_command_run!(command_run_id)
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
                    Fenix::Runtime::CommandRunRegistry.append_output(
                      command_run_id:,
                      stream: stream_details.fetch(:stream),
                      text: chunk
                    )
                    emit_tool_output!(
                      command_run_id:,
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

          def start_command_run_session
            check_canceled!
            command_run_id = @command_run.fetch("command_run_id")
            stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", @tool_call.dig("arguments", "command_line").to_s)
            Fenix::Runtime::CommandRunRegistry.register(
              command_run_id:,
              agent_task_run_id: @current_agent_task_run_id,
              stdin:,
              stdout:,
              stderr:,
              wait_thread:
            )
            activate_registered_command_run!(command_run_id)

            {
              "command_run_id" => command_run_id,
              "attached" => true,
              "session_closed" => false,
              "timeout_seconds" => @tool_call.dig("arguments", "timeout_seconds").to_i,
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

          def read_available_output(command_run:, timeout_seconds:, command_run_id: command_run.command_run_id)
            readers = {}
            readers[command_run.stdout] = "stdout" unless command_run.stdout.closed?
            readers[command_run.stderr] = "stderr" unless command_run.stderr.closed?
            return [] if readers.empty?

            ready = IO.select(readers.keys, nil, nil, timeout_seconds)
            return [] if ready.blank?

            ready.first.each_with_object([]) do |io, output_chunks|
              begin
                chunk = io.read_nonblock(4096)
                next if chunk.blank?

                stream = readers.fetch(io)
                Fenix::Runtime::CommandRunRegistry.append_output(
                  command_run_id: command_run.command_run_id,
                  stream: stream,
                  text: chunk
                )
                output_chunks << { "stream" => stream, "text" => chunk }
              rescue IO::WaitReadable
                nil
              rescue EOFError
                nil
              end
            end
          end

          def emit_tool_output!(output_chunks:, command_run_id:)
            return if canceled?

            @collector.progress!(
              progress_payload: {
                "stage" => "tool_output",
                "tool_invocation_output" => {
                  "tool_invocation_id" => @tool_invocation.fetch("tool_invocation_id"),
                  "call_id" => @tool_call.fetch("call_id"),
                  "tool_name" => @tool_call.fetch("tool_name"),
                  "command_run_id" => command_run_id,
                  "output_chunks" => output_chunks,
                },
              }
            )
          end

          def activate_registered_command_run!(command_run_id)
            @control_client.activate_command_run!(command_run_id:)
          rescue StandardError
            Fenix::Runtime::CommandRunRegistry.terminate(command_run_id:)
            raise
          end

          def lookup_owned_command_run!(command_run_id)
            command_run = Fenix::Runtime::CommandRunRegistry.lookup(command_run_id:)
            raise ArgumentError, "unknown command run #{command_run_id}" if command_run.blank?
            raise ArgumentError, "command run #{command_run_id} is not owned by this agent task" unless command_run.agent_task_run_id == @current_agent_task_run_id

            command_run
          end

          def terminate_subprocess!(pid:)
            return if pid.blank?

            ::Process.kill("TERM", pid)
            sleep(0.1)
            ::Process.kill("KILL", pid)
          rescue Errno::ESRCH
            nil
          end

          def monotonic_now
            ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          end

          def canceled?
            @cancellation_probe&.call == true
          end

          def check_canceled!
            raise CancellationRequestedError, "execution canceled" if canceled?
          end
        end
      end
    end
  end
end
