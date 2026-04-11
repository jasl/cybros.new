require "open3"
require "securerandom"

module Nexus
  module ExecutionRuntime
    module ToolExecutors
      module ExecCommand
        class ValidationError < StandardError; end
        class CancellationRequestedError < StandardError; end

        class << self
          def call(tool_call:, context:, collector:, cancellation_probe:, current_runtime_owner_id:, command_run: nil, **)
            new_runtime(
              tool_call: tool_call,
              context: context,
              collector: collector,
              cancellation_probe: cancellation_probe,
              current_runtime_owner_id: current_runtime_owner_id,
              command_run: command_run
            ).call
          end

          private

          def new_runtime(...)
            Runtime.new(...)
          end
        end

        class Runtime
          def initialize(tool_call:, context:, collector:, cancellation_probe:, current_runtime_owner_id:, command_run: nil)
            @tool_call = tool_call.deep_stringify_keys
            @context = context.deep_stringify_keys
            @collector = collector
            @cancellation_probe = cancellation_probe
            @current_runtime_owner_id = current_runtime_owner_id
            @command_run = command_run&.deep_stringify_keys
            @workspace_root = resolve_workspace_root
          end

          def call
            case @tool_call.fetch("tool_name")
            when "command_run_list"
              { "entries" => Nexus::ExecutionRuntime::CommandRunRegistry.list(runtime_owner_id: @current_runtime_owner_id) }
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
              raise ValidationError, "unsupported exec command tool #{@tool_call.fetch("tool_name")}"
            end
          end

          private

          def execute_exec_command
            return start_command_run_session if @tool_call.dig("arguments", "pty")

            execute_one_shot_command(
              command_line: @tool_call.dig("arguments", "command_line"),
              timeout_seconds: (@tool_call.dig("arguments", "timeout_seconds") || 30).to_i,
              timeout_label: @tool_call.fetch("tool_name")
            )
          end

          def execute_write_stdin
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id").to_s
            command_run = lookup_owned_command_run!(command_run_id)

            text = @tool_call.dig("arguments", "text").to_s
            wait_for_exit = @tool_call.dig("arguments", "wait_for_exit")
            timeout_seconds = (@tool_call.dig("arguments", "timeout_seconds") || 30).to_i
            stdin_bytes = text.bytesize

            command_run.stdin.write(text) if text.present?
            command_run.stdin.flush if text.present?
            command_run.stdin.close if @tool_call.dig("arguments", "eof") && !command_run.stdin.closed?

            output_chunks = drain_attached_output(
              command_run: command_run,
              wait_for_exit: wait_for_exit,
              timeout_seconds: timeout_seconds,
              timeout_label: @tool_call.fetch("tool_name")
            )
            emit_tool_output!(command_run_id: command_run_id, output_chunks: output_chunks) if output_chunks.any?

            snapshot = Nexus::ExecutionRuntime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id) || {
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
            Nexus::ExecutionRuntime::CommandRunRegistry.release(command_run_id: command_run_id) if wait_for_exit && command_run_id.present? && !command_run&.session_closed
          end

          def execute_command_run_read_output
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id").to_s
            command_run = lookup_owned_command_run!(command_run_id)
            output_chunks =
              if command_run.session_closed
                []
              else
                read_available_output(command_run: command_run, timeout_seconds: 0.05, command_run_id: command_run_id)
              end
            emit_tool_output!(command_run_id: command_run_id, output_chunks: output_chunks) if output_chunks.any?

            snapshot = Nexus::ExecutionRuntime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)
            raise ValidationError, "unknown command run #{command_run_id}" if snapshot.blank?

            snapshot
          end

          def execute_command_run_wait
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id").to_s
            timeout_seconds = (@tool_call.dig("arguments", "timeout_seconds") || 30).to_i
            command_run = lookup_owned_command_run!(command_run_id)

            if command_run.session_closed
              snapshot = Nexus::ExecutionRuntime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)
              raise ValidationError, "unknown command run #{command_run_id}" if snapshot.blank?

              return snapshot.merge(
                "session_closed" => true,
                "output_streamed" => snapshot.fetch("stdout_bytes").positive? || snapshot.fetch("stderr_bytes").positive?
              )
            end

            timed_out = false
            output_chunks = []

            begin
              output_chunks = drain_attached_output(
                command_run: command_run,
                wait_for_exit: true,
                timeout_seconds: timeout_seconds,
                timeout_label: @tool_call.fetch("tool_name")
              )
            rescue Timeout::Error
              timed_out = true
            ensure
              emit_tool_output!(command_run_id: command_run_id, output_chunks: output_chunks) if output_chunks.any?
            end

            snapshot = Nexus::ExecutionRuntime::CommandRunRegistry.output_snapshot(command_run_id: command_run_id)

            if timed_out
              return snapshot&.merge(
                "session_closed" => false,
                "timed_out" => true,
                "output_streamed" => snapshot.fetch("stdout_bytes").positive? || snapshot.fetch("stderr_bytes").positive?
              ) || {
                "command_run_id" => command_run_id,
                "session_closed" => false,
                "timed_out" => true,
                "lifecycle_state" => "running",
                "output_streamed" => false,
                "stdout_bytes" => 0,
                "stderr_bytes" => 0,
                "stdout_tail" => "",
                "stderr_tail" => "",
              }
            end

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
            Nexus::ExecutionRuntime::CommandRunRegistry.release(command_run_id: command_run_id) if command_run_id.present? && !command_run&.session_closed
          end

          def execute_command_run_terminate
            check_canceled!
            command_run_id = @tool_call.dig("arguments", "command_run_id").to_s
            lookup_owned_command_run!(command_run_id)

            snapshot = Nexus::ExecutionRuntime::CommandRunRegistry.terminate(command_run_id: command_run_id)
            raise ValidationError, "unknown command run #{command_run_id}" if snapshot.blank?

            snapshot
          end

          def start_command_run_session
            check_canceled!
            command_run_id = normalized_command_run_id
            stdin, stdout, stderr, wait_thread = Open3.popen3(
              command_environment,
              "/bin/sh",
              "-lc",
              command_line.to_s,
              chdir: @workspace_root,
              pgroup: true
            )
            Nexus::ExecutionRuntime::CommandRunRegistry.register(
              command_run_id: command_run_id,
              runtime_owner_id: @current_runtime_owner_id,
              stdin: stdin,
              stdout: stdout,
              stderr: stderr,
              wait_thread: wait_thread
            )

            {
              "command_run_id" => command_run_id,
              "attached" => true,
              "session_closed" => false,
              "timeout_seconds" => timeout_seconds,
            }
          end

          def execute_one_shot_command(command_line:, timeout_seconds:, timeout_label:)
            check_canceled!
            stdout = +""
            stderr = +""
            process_pid = nil
            preserve_snapshot = false
            command_run_id = normalized_command_run_id
            stdin, command_stdout, command_stderr, wait_thr = Open3.popen3(
              command_environment,
              "/bin/sh",
              "-lc",
              command_line.to_s,
              chdir: @workspace_root,
              pgroup: true
            )

            Nexus::ExecutionRuntime::CommandRunRegistry.register(
              command_run_id: command_run_id,
              runtime_owner_id: @current_runtime_owner_id,
              stdin: stdin,
              stdout: command_stdout,
              stderr: command_stderr,
              wait_thread: wait_thr
            )
            process_pid = wait_thr.pid
            stdin.close

            deadline_at = monotonic_now + timeout_seconds
            readers = {
              command_stdout => { stream: "stdout", buffer: stdout },
              command_stderr => { stream: "stderr", buffer: stderr },
            }
            stream_byte_counts = Hash.new(0)

            loop do
              check_canceled!
              if wait_thr.alive?
                remaining = deadline_at - monotonic_now
                raise Timeout::Error, "#{timeout_label} timed out after #{timeout_seconds} seconds" if remaining <= 0

                capture_ready_output!(
                  readers: readers,
                  command_run_id: command_run_id,
                  timeout_seconds: [remaining, 0.1].min,
                  stream_byte_counts: stream_byte_counts
                )

                next
              end

              capture_ready_output!(
                readers: readers,
                command_run_id: command_run_id,
                timeout_seconds: 0,
                stream_byte_counts: stream_byte_counts
              )
              break if readers.empty?
              sleep(0.01)
            end

            exit_status = wait_thr.value.exitstatus
            preserve_snapshot = true

            {
              "command_run_id" => command_run_id,
              "exit_status" => exit_status,
              "stdout" => stdout,
              "stderr" => stderr,
              "stdout_bytes" => stream_byte_counts["stdout"],
              "stderr_bytes" => stream_byte_counts["stderr"],
              "output_streamed" => stream_byte_counts["stdout"].positive? || stream_byte_counts["stderr"].positive?,
            }
          rescue Timeout::Error
            terminate_subprocess!(pid: process_pid)
            raise
          ensure
            stdin&.close unless stdin.nil? || stdin.closed?
            command_stdout&.close unless command_stdout.nil? || command_stdout.closed?
            command_stderr&.close unless command_stderr.nil? || command_stderr.closed?
            if command_run_id.present?
              if preserve_snapshot
                Nexus::ExecutionRuntime::CommandRunRegistry.release(command_run_id: command_run_id)
              else
                Nexus::ExecutionRuntime::CommandRunRegistry.terminate(command_run_id: command_run_id)
              end
            end
          end

          def drain_attached_output(command_run:, wait_for_exit:, timeout_seconds:, timeout_label:)
            chunks = []
            timeout_seconds = 30 if wait_for_exit && timeout_seconds <= 0
            deadline_at = monotonic_now + timeout_seconds

            loop do
              check_canceled!
              chunks.concat(read_available_output(command_run: command_run, timeout_seconds: 0.05))
              break unless wait_for_exit
              break unless command_run.wait_thread.alive?
              raise Timeout::Error, "#{timeout_label} timed out after #{timeout_seconds} seconds" if monotonic_now >= deadline_at
            end

            chunks.concat(read_available_output(command_run: command_run, timeout_seconds: 0.05))
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
              status, chunk = safe_nonblock_read(io)
              next if status == :wait || status == :eof || chunk.blank?

              stream = readers.fetch(io)
              sanitized = Nexus::ExecutionRuntime::CommandRunRegistry.sanitize_output_text(chunk)
              Nexus::ExecutionRuntime::CommandRunRegistry.append_output(
                command_run_id: command_run_id,
                stream: stream,
                text: sanitized
              )
              output_chunks << {
                "command_run_id" => command_run_id,
                "stream" => stream,
                "text" => sanitized,
              }
            end
          end

          def capture_ready_output!(readers:, command_run_id:, timeout_seconds:, stream_byte_counts:)
            ready = IO.select(readers.keys, nil, nil, timeout_seconds)
            return if ready.blank?

            output_chunks = []

            ready.first.each do |io|
              status, chunk = safe_nonblock_read(io)
              if status == :eof
                readers.delete(io)
                next
              end
              next if status == :wait || chunk.blank?

              metadata = readers.fetch(io)
              stream = metadata.fetch(:stream)
              sanitized = Nexus::ExecutionRuntime::CommandRunRegistry.sanitize_output_text(chunk)
              metadata.fetch(:buffer) << sanitized
              stream_byte_counts[stream] += chunk.bytesize
              Nexus::ExecutionRuntime::CommandRunRegistry.append_output(
                command_run_id: command_run_id,
                stream: stream,
                text: sanitized
              )
              output_chunks << {
                "command_run_id" => command_run_id,
                "stream" => stream,
                "text" => sanitized,
              }
            rescue EOFError, IOError
              readers.delete(io)
            end

            emit_tool_output!(command_run_id: command_run_id, output_chunks: output_chunks) if output_chunks.any?
          end

          def safe_nonblock_read(io)
            [:data, io.read_nonblock(4096)]
          rescue IO::WaitReadable
            [:wait, nil]
          rescue EOFError, IOError
            [:eof, nil]
          end

          def emit_tool_output!(command_run_id:, output_chunks:)
            @collector.progress!(
              progress_payload: {
                "tool_invocation_output" => {
                  "command_run_id" => command_run_id,
                  "output_chunks" => output_chunks,
                },
              }
            )
          end

          def lookup_owned_command_run!(command_run_id)
            command_run = Nexus::ExecutionRuntime::CommandRunRegistry.lookup(command_run_id: command_run_id)
            raise ValidationError, "unknown command run #{command_run_id}" if command_run.blank?
            unless command_run.runtime_owner_id == @current_runtime_owner_id
              raise ValidationError, "command run #{command_run_id} is not owned by this execution"
            end

            command_run
          end

          def resolve_workspace_root
            root = @context.dig("workspace_context", "workspace_root").presence ||
              ENV["NEXUS_WORKSPACE_ROOT"].presence ||
              "/workspace"
            Pathname.new(root).expand_path.to_s
          end

          def command_environment
            ENV.to_h.merge(workspace_env_overlay)
          end

          def workspace_env_overlay
            @workspace_env_overlay ||= Nexus::Shared::Environment::WorkspaceEnvOverlay.call(
              workspace_root: @workspace_root
            )
          rescue Nexus::Shared::Environment::WorkspaceEnvOverlay::ValidationError => error
            raise ValidationError, error.message
          end

          def terminate_subprocess!(pid:)
            return if pid.blank?

            process_pid = pid.to_i
            [(-process_pid), process_pid].each do |target|
              ::Process.kill("TERM", target)
              sleep(0.1)
              ::Process.kill("KILL", target)
              return
            rescue Errno::ESRCH
              next
            end
          end

          def check_canceled!
            raise CancellationRequestedError, "execution canceled" if @cancellation_probe&.call
          end

          def normalized_command_run_id
            @command_run&.fetch("command_run_id", nil).presence ||
              "command-run-#{@tool_call.fetch("call_id", SecureRandom.uuid)}"
          end

          def command_line
            @tool_call.dig("arguments", "command_line").to_s
          end

          def timeout_seconds
            (@tool_call.dig("arguments", "timeout_seconds") || 30).to_i
          end

          def monotonic_now
            ::Process.clock_gettime(::Process::CLOCK_MONOTONIC)
          end
        end
      end
    end
  end
end
