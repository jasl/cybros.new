module Fenix
  module Runtime
    class AttachedCommandSessionRegistry
      Entry = Struct.new(
        :session_id,
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
        def register(agent_task_run_id:, stdin:, stdout:, stderr:, wait_thread:)
          session_id = "session-#{SecureRandom.uuid}"

          synchronize do
            entries[session_id] = Entry.new(
              session_id: session_id,
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

        def lookup(session_id:)
          synchronize do
            entries[session_id]
          end
        end

        def release(session_id:)
          synchronize do
            entries.delete(session_id)
          end
        end

        def release_for_agent_task(agent_task_run_id:)
          synchronize do
            entries.delete_if { |_session_id, entry| entry.agent_task_run_id == agent_task_run_id }
          end
        end

        def reset!
          synchronize do
            entries.clear
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
      end
    end
  end
end
