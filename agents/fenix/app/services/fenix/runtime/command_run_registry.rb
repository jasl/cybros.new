module Fenix
  module Runtime
    class CommandRunRegistry
      # Attached command handles are runtime-local execution projections.
      # Kernel-owned CommandRun records remain the only durable source of truth.
      LocalHandle = Struct.new(
        :command_run_id,
        :agent_task_run_id,
        :stdin,
        :stdout,
        :stderr,
        :wait_thread,
        :stdout_bytes,
        :stderr_bytes,
        :stdout_tail,
        :stderr_tail,
        keyword_init: true
      )

      class << self
        OUTPUT_TAIL_LIMIT_BYTES = 8192

        def register(command_run_id:, agent_task_run_id:, stdin:, stdout:, stderr:, wait_thread:)
          synchronize do
            entries[command_run_id] = LocalHandle.new(
              command_run_id: command_run_id,
              agent_task_run_id: agent_task_run_id,
              stdin: stdin,
              stdout: stdout,
              stderr: stderr,
              wait_thread: wait_thread,
              stdout_bytes: 0,
              stderr_bytes: 0,
              stdout_tail: +"",
              stderr_tail: +""
            )
          end
        end

        def append_output(command_run_id:, stream:, text:)
          synchronize do
            entry = entries[command_run_id]
            return if entry.blank?

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

        def list(agent_task_run_id: nil)
          synchronize do
            entries.values
              .select { |entry| agent_task_run_id.blank? || entry.agent_task_run_id == agent_task_run_id }
              .sort_by(&:command_run_id)
              .map { |entry| snapshot_for(entry) }
          end
        end

        def lookup(command_run_id:)
          synchronize do
            entries[command_run_id]
          end
        end

        def output_snapshot(command_run_id:)
          synchronize do
            entry = entries[command_run_id]
            snapshot_for(entry) if entry.present?
          end
        end

        def release(command_run_id:)
          terminate(command_run_id:)
        end

        def terminate(command_run_id:)
          entry = synchronize do
            entries.delete(command_run_id)
          end
          return if entry.nil?

          terminate_entry(entry)
          snapshot_for(entry).merge(
            "terminated" => true,
            "session_closed" => true,
            "exit_status" => exit_status_for(entry)
          )
        end

        def terminate_for_agent_task(agent_task_run_id:)
          command_runs = synchronize do
            entries.values.select { |entry| entry.agent_task_run_id == agent_task_run_id }
          end

          command_runs.each do |entry|
            terminate_entry(entry)
          end

          synchronize do
            entries.delete_if { |_command_run_id, entry| entry.agent_task_run_id == agent_task_run_id }
          end
        end

        def reset!
          command_runs = synchronize do
            entries.values.tap { entries.clear }
          end

          command_runs.each do |entry|
            terminate_entry(entry)
          end
        end

        private

        def entries
          @entries ||= {}
        end

        def mutex
          @mutex ||= Mutex.new
        end

        def synchronize(&block)
          mutex.synchronize(&block)
        end

        def snapshot_for(entry)
          {
            "command_run_id" => entry.command_run_id,
            "agent_task_run_id" => entry.agent_task_run_id,
            "lifecycle_state" => entry.wait_thread&.alive? ? "running" : "stopped",
            "stdout_bytes" => entry.stdout_bytes,
            "stderr_bytes" => entry.stderr_bytes,
            "stdout_tail" => entry.stdout_tail.dup,
            "stderr_tail" => entry.stderr_tail.dup,
          }
        end

        def trim_tail(existing, text)
          combined = +"#{existing}#{text}"
          bytes = combined.bytes
          return combined if bytes.length <= OUTPUT_TAIL_LIMIT_BYTES

          bytes.last(OUTPUT_TAIL_LIMIT_BYTES).pack("C*").force_encoding(combined.encoding)
        end

        def terminate_entry(entry)
          entry.stdin.close unless entry.stdin.closed?
          pid = entry.wait_thread.pid
          Process.kill("TERM", pid)
          sleep(0.1)
          Process.kill("KILL", pid)
        rescue IOError, Errno::ESRCH
          nil
        ensure
          entry.stdout.close unless entry.stdout.closed?
          entry.stderr.close unless entry.stderr.closed?
          join_wait_thread(entry.wait_thread)
        end

        def join_wait_thread(wait_thread)
          return if wait_thread.nil? || wait_thread == Thread.current

          wait_thread.join(0.5)
        rescue StandardError
          nil
        end

        def exit_status_for(entry)
          entry.wait_thread&.value&.exitstatus
        rescue StandardError
          nil
        end
      end
    end
  end
end
