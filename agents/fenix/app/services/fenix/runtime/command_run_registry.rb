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
        keyword_init: true
      )

      class << self
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
              stderr_bytes: 0
            )
          end
        end

        def lookup(command_run_id:)
          synchronize do
            entries[command_run_id]
          end
        end

        def release(command_run_id:)
          synchronize do
            entries.delete(command_run_id)
          end
        end

        def terminate(command_run_id:)
          entry = synchronize do
            entries.delete(command_run_id)
          end
          return if entry.nil?

          terminate_entry(entry)
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
      end
    end
  end
end
