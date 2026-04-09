module Fenix
  module Runtime
    class CommandRunRegistry
      LocalHandle = Struct.new(
        :command_run_id,
        :runtime_owner_id,
        :stdin,
        :stdout,
        :stderr,
        :wait_thread,
        :session_closed,
        :exit_status,
        :stdout_bytes,
        :stderr_bytes,
        :stdout_tail,
        :stderr_tail,
        keyword_init: true
      )

      class << self
        OUTPUT_TAIL_LIMIT_BYTES = 8192

        def sanitize_output_text(text)
          sanitized = text.to_s.dup.force_encoding(Encoding::UTF_8)
          sanitized.valid_encoding? ? sanitized : sanitized.scrub
        end

        def register(command_run_id:, runtime_owner_id:, stdin:, stdout:, stderr:, wait_thread:)
          registry.store(
            LocalHandle.new(
              command_run_id: command_run_id,
              runtime_owner_id: runtime_owner_id,
              stdin: stdin,
              stdout: stdout,
              stderr: stderr,
              wait_thread: wait_thread,
              session_closed: false,
              exit_status: nil,
              stdout_bytes: 0,
              stderr_bytes: 0,
              stdout_tail: +"",
              stderr_tail: +""
            )
          )
        end

        def append_output(command_run_id:, stream:, text:)
          registry.mutate(key: command_run_id) do |entry|
            bytes = text.to_s.bytesize
            case stream
            when "stdout"
              entry.stdout_bytes += bytes
              entry.stdout_tail = trim_tail(entry.stdout_tail, text)
            when "stderr"
              entry.stderr_bytes += bytes
              entry.stderr_tail = trim_tail(entry.stderr_tail, text)
            else
              raise ArgumentError, "unsupported command run stream #{stream}"
            end

            snapshot_for(entry)
          end
        end

        def list(runtime_owner_id: nil)
          registry.project_list(runtime_owner_id: runtime_owner_id) { |entry| snapshot_for(entry) }
        end

        def lookup(command_run_id:)
          registry.lookup(key: command_run_id)
        end

        def output_snapshot(command_run_id:)
          registry.project_entry(key: command_run_id) { |entry| snapshot_for(entry) }
        end

        def release(command_run_id:)
          entry = lookup(command_run_id: command_run_id)
          return if entry.nil?

          return snapshot_for(entry) if entry.wait_thread&.alive? && !entry.session_closed

          registry.remove(key: command_run_id)
          close_entry(entry)
          snapshot_for(entry)
        end

        def terminate(command_run_id:)
          entry = registry.remove(key: command_run_id)
          return if entry.nil?

          close_entry(entry, signal_process: true)
          snapshot_for(entry).merge(
            "terminated" => true,
            "session_closed" => true
          )
        end

        def reset!
          command_runs = registry.clear!

          command_runs.each do |entry|
            close_entry(entry, signal_process: true)
          end
        end

        private

        def registry
          @registry ||= Fenix::Runtime::OwnedResourceRegistry.new(key_attr: :command_run_id)
        end

        def snapshot_for(entry)
          {
            "command_run_id" => entry.command_run_id,
            "runtime_owner_id" => entry.runtime_owner_id,
            "lifecycle_state" => entry.session_closed || !entry.wait_thread&.alive? ? "stopped" : "running",
            "session_closed" => entry.session_closed,
            "exit_status" => entry.exit_status,
            "stdout_bytes" => entry.stdout_bytes,
            "stderr_bytes" => entry.stderr_bytes,
            "stdout_tail" => entry.stdout_tail.dup,
            "stderr_tail" => entry.stderr_tail.dup,
          }.compact
        end

        def trim_tail(existing, text)
          combined = +"#{sanitize_output_text(existing)}#{sanitize_output_text(text)}"
          bytes = combined.bytes
          return combined if bytes.length <= OUTPUT_TAIL_LIMIT_BYTES

          bytes.last(OUTPUT_TAIL_LIMIT_BYTES).pack("C*").force_encoding(combined.encoding)
        end

        def close_entry(entry, signal_process: false)
          registry.synchronize do
            return if entry.session_closed

            entry.stdin.close unless entry.stdin.closed?
            if signal_process && entry.wait_thread&.alive?
              pid = entry.wait_thread.pid
              signal_process_tree!("TERM", pid)
              sleep(0.1)
              signal_process_tree!("KILL", pid) if entry.wait_thread&.alive?
            end
          end
        rescue IOError, Errno::EPERM, Errno::ESRCH
          nil
        ensure
          entry.stdout.close unless entry.stdout.closed?
          entry.stderr.close unless entry.stderr.closed?
          join_wait_thread(entry.wait_thread)
          registry.synchronize do
            entry.exit_status ||= exit_status_for(entry)
            entry.session_closed = true
          end
        end

        def join_wait_thread(wait_thread)
          return if wait_thread.nil? || wait_thread == Thread.current

          wait_thread.join(0.5)
        rescue StandardError
          nil
        end

        def exit_status_for(entry)
          wait_thread = entry.wait_thread
          return nil if wait_thread.nil? || wait_thread.alive?

          wait_thread.value&.exitstatus
        rescue StandardError
          nil
        end

        def signal_process_tree!(signal, pid)
          process_pid = pid.to_i
          [(-process_pid), process_pid].each do |target|
            Process.kill(signal, target)
            return
          rescue Errno::ESRCH
            next
          end

          raise Errno::ESRCH, process_pid.to_s
        end
      end
    end
  end
end
