require "json"
require "open3"
require "securerandom"
require "timeout"

module CybrosNexus
  module Resources
    class CommandHost
      ValidationError = Class.new(StandardError)

      Handle = Struct.new(
        :command_run_id,
        :runtime_owner_id,
        :stdin,
        :stdout,
        :wait_thread,
        :pid,
        :session_closed,
        :exit_status,
        :stdout_bytes,
        :stderr_bytes,
        :stdout_tail,
        :stderr_tail,
        keyword_init: true
      )

      OUTPUT_TAIL_LIMIT_BYTES = 8_192
      READ_CHUNK_SIZE = 4_096

      def initialize(store:)
        @store = store
        @handles = {}
        @mutex = Mutex.new
      end

      def start(command_run_id:, runtime_owner_id:, command_line:, pty:, workdir:, environment: {})
        if pty
          start_attached_session(
            command_run_id: command_run_id,
            runtime_owner_id: runtime_owner_id,
            command_line: command_line,
            workdir: workdir,
            environment: environment
          )
        else
          run_one_shot(
            command_run_id: command_run_id,
            runtime_owner_id: runtime_owner_id,
            command_line: command_line,
            workdir: workdir,
            environment: environment
          )
        end
      end

      def list(runtime_owner_id: nil)
        @mutex.synchronize do
          @handles.values
            .select { |handle| runtime_owner_id.nil? || handle.runtime_owner_id == runtime_owner_id }
            .map { |handle| snapshot_for(handle) }
        end
      end

      def read_output(command_run_id:, runtime_owner_id:, timeout_seconds: 0.05)
        handle = lookup_owned_handle!(command_run_id:, runtime_owner_id:)
        capture_available_output!(handle, timeout_seconds: timeout_seconds)
        snapshot_for(handle)
      end

      def write_stdin(command_run_id:, runtime_owner_id:, text: nil, eof: false, wait_for_exit: false, timeout_seconds: 30)
        handle = lookup_owned_handle!(command_run_id:, runtime_owner_id:)

        if text && !text.empty?
          handle.stdin.write(text)
          handle.stdin.flush
        end
        handle.stdin.close if eof && !handle.stdin.closed?

        capture_available_output!(handle, timeout_seconds: 0.05)
        return wait(command_run_id:, runtime_owner_id:, timeout_seconds:) if wait_for_exit

        snapshot_for(handle)
      end

      def wait(command_run_id:, runtime_owner_id:, timeout_seconds:)
        handle = lookup_owned_handle!(command_run_id:, runtime_owner_id:)
        deadline_at = monotonic_now + timeout_seconds.to_f

        loop do
          capture_available_output!(handle, timeout_seconds: 0.05)

          unless handle.wait_thread.alive?
            finalize_handle!(handle)
            return snapshot_for(handle).merge(
              "session_closed" => true
            )
          end

          return snapshot_for(handle).merge("timed_out" => true) if monotonic_now >= deadline_at
        end
      end

      def terminate(command_run_id:, runtime_owner_id:)
        handle = remove_owned_handle!(command_run_id:, runtime_owner_id:)

        terminate_process_tree!(handle.pid, signal: "TERM")
        sleep(0.1)
        terminate_process_tree!(handle.pid, signal: "KILL") if handle.wait_thread.alive?
        finalize_handle!(handle)

        snapshot_for(handle).merge(
          "terminated" => true,
          "session_closed" => true
        )
      end

      def shutdown
        handles =
          @mutex.synchronize do
            current = @handles.values
            @handles = {}
            current
          end

        handles.each do |handle|
          terminate_process_tree!(handle.pid, signal: "TERM")
          sleep(0.05)
          terminate_process_tree!(handle.pid, signal: "KILL") if handle.wait_thread.alive?
          finalize_handle!(handle)
        end
      end

      private

      def start_attached_session(command_run_id:, runtime_owner_id:, command_line:, workdir:, environment:)
        stdin, stdout, wait_thread = Open3.popen2e(
          environment,
          "script",
          "-q",
          "/dev/null",
          "/bin/sh",
          "-lc",
          command_line.to_s,
          chdir: workdir,
          pgroup: true
        )

        handle = Handle.new(
          command_run_id: command_run_id,
          runtime_owner_id: runtime_owner_id,
          stdin: stdin,
          stdout: stdout,
          wait_thread: wait_thread,
          pid: wait_thread.pid,
          session_closed: false,
          exit_status: nil,
          stdout_bytes: 0,
          stderr_bytes: 0,
          stdout_tail: +"",
          stderr_tail: +""
        )

        @mutex.synchronize { @handles[command_run_id] = handle }
        persist_handle!(handle, state: "running")

        {
          "command_run_id" => command_run_id,
          "attached" => true,
          "session_closed" => false,
        }
      end

      def run_one_shot(command_run_id:, runtime_owner_id:, command_line:, workdir:, environment:)
        stdin, stdout, stderr, wait_thread = Open3.popen3(
          environment,
          "/bin/sh",
          "-lc",
          command_line.to_s,
          chdir: workdir,
          pgroup: true
        )
        stdin.close

        stdout_reader = Thread.new { stdout.read.to_s }
        stderr_reader = Thread.new { stderr.read.to_s }

        status =
          Timeout.timeout(30) do
            wait_thread.value
          end

        result = {
          "command_run_id" => command_run_id,
          "session_closed" => true,
          "exit_status" => status.exitstatus,
          "stdout" => sanitize_output_text(stdout_reader.value),
          "stderr" => sanitize_output_text(stderr_reader.value),
        }
        result["stdout_bytes"] = result.fetch("stdout").bytesize
        result["stderr_bytes"] = result.fetch("stderr").bytesize
        result["stdout_tail"] = trim_tail("", result.fetch("stdout"))
        result["stderr_tail"] = trim_tail("", result.fetch("stderr"))

        persist_snapshot!(
          resource_id: command_run_id,
          resource_type: "CommandRun",
          state: "stopped",
          metadata: {
            "runtime_owner_id" => runtime_owner_id,
            "session_closed" => true,
            "exit_status" => result["exit_status"],
            "stdout_bytes" => result["stdout_bytes"],
            "stderr_bytes" => result["stderr_bytes"],
            "stdout_tail" => result["stdout_tail"],
            "stderr_tail" => result["stderr_tail"],
          }
        )

        result
      ensure
        stdin&.close unless stdin.nil? || stdin.closed?
        stdout&.close unless stdout.nil? || stdout.closed?
        stderr&.close unless stderr.nil? || stderr.closed?
        wait_thread&.join(0.1)
      end

      def lookup_owned_handle!(command_run_id:, runtime_owner_id:)
        handle =
          @mutex.synchronize do
            @handles[command_run_id]
          end
        raise ValidationError, "unknown command run #{command_run_id}" if handle.nil?
        raise ValidationError, "command run #{command_run_id} is not owned by this execution" if handle.runtime_owner_id != runtime_owner_id

        handle
      end

      def remove_owned_handle!(command_run_id:, runtime_owner_id:)
        handle =
          @mutex.synchronize do
            @handles.delete(command_run_id)
          end
        raise ValidationError, "unknown command run #{command_run_id}" if handle.nil?
        raise ValidationError, "command run #{command_run_id} is not owned by this execution" if handle.runtime_owner_id != runtime_owner_id

        handle
      end

      def capture_available_output!(handle, timeout_seconds:)
        readers = [handle.stdout].compact.reject(&:closed?)
        return if readers.empty?

        timeout = timeout_seconds

        loop do
          ready, = IO.select(readers, nil, nil, timeout)
          break if ready.nil? || ready.empty?

          ready.each do |io|
            begin
              chunk = io.read_nonblock(READ_CHUNK_SIZE)
              append_output!(handle, stream: "stdout", text: chunk)
            rescue EOFError, Errno::EIO
              readers.delete(io)
            rescue IO::WaitReadable
              nil
            end
          end

          timeout = 0
        end
      end

      def append_output!(handle, stream:, text:)
        bytes = text.to_s.bytesize

        case stream
        when "stdout"
          handle.stdout_bytes += bytes
          handle.stdout_tail = trim_tail(handle.stdout_tail, text)
        when "stderr"
          handle.stderr_bytes += bytes
          handle.stderr_tail = trim_tail(handle.stderr_tail, text)
        else
          raise ArgumentError, "unsupported command stream #{stream}"
        end

        persist_handle!(handle, state: handle.session_closed ? "stopped" : "running")
      end

      def finalize_handle!(handle)
        handle.stdin.close unless handle.stdin.closed?
        handle.stdout.close unless handle.stdout.closed?
        handle.wait_thread.join(0.5)
        handle.exit_status = handle.wait_thread.value&.exitstatus
        handle.session_closed = true
        persist_handle!(handle, state: "stopped")
      rescue IOError, Errno::ECHILD
        handle.session_closed = true
        persist_handle!(handle, state: "stopped")
      end

      def snapshot_for(handle)
        {
          "command_run_id" => handle.command_run_id,
          "runtime_owner_id" => handle.runtime_owner_id,
          "lifecycle_state" => handle.session_closed ? "stopped" : "running",
          "session_closed" => handle.session_closed,
          "exit_status" => handle.exit_status,
          "stdout_bytes" => handle.stdout_bytes,
          "stderr_bytes" => handle.stderr_bytes,
          "stdout_tail" => handle.stdout_tail.dup,
          "stderr_tail" => handle.stderr_tail.dup,
        }.compact
      end

      def persist_handle!(handle, state:)
        persist_snapshot!(
          resource_id: handle.command_run_id,
          resource_type: "CommandRun",
          state: state,
          metadata: {
            "runtime_owner_id" => handle.runtime_owner_id,
            "session_closed" => handle.session_closed,
            "exit_status" => handle.exit_status,
            "stdout_bytes" => handle.stdout_bytes,
            "stderr_bytes" => handle.stderr_bytes,
            "stdout_tail" => handle.stdout_tail,
            "stderr_tail" => handle.stderr_tail,
          }
        )
      end

      def persist_snapshot!(resource_id:, resource_type:, state:, metadata:)
        @store.database.execute(
          <<~SQL,
            INSERT INTO resource_handles (resource_id, resource_type, state, metadata_json, updated_at)
            VALUES (?, ?, ?, ?, ?)
            ON CONFLICT(resource_id) DO UPDATE SET
              resource_type = excluded.resource_type,
              state = excluded.state,
              metadata_json = excluded.metadata_json,
              updated_at = excluded.updated_at
          SQL
          [
            resource_id,
            resource_type,
            state,
            JSON.generate(metadata),
            Time.now.utc.iso8601,
          ]
        )
      end

      def sanitize_output_text(text)
        sanitized = text.to_s.dup.force_encoding(Encoding::UTF_8)
        sanitized.valid_encoding? ? sanitized : sanitized.scrub
      end

      def trim_tail(existing, text)
        combined = +"#{sanitize_output_text(existing)}#{sanitize_output_text(text)}"
        bytes = combined.bytes
        return combined if bytes.length <= OUTPUT_TAIL_LIMIT_BYTES

        bytes.last(OUTPUT_TAIL_LIMIT_BYTES).pack("C*").force_encoding(combined.encoding)
      end

      def terminate_process_tree!(pid, signal:)
        [(-pid.to_i), pid.to_i].each do |target|
          Process.kill(signal, target)
          return
        rescue Errno::ESRCH
          next
        end
      rescue Errno::EPERM
        nil
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
