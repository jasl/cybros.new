module Fenix
  module Runtime
    class AttemptRegistry
      Entry = Struct.new(
        :agent_task_run_id,
        :logical_work_id,
        :attempt_no,
        :runtime_execution_id,
        keyword_init: true
      )

      class << self
        def register(agent_task_run_id:, logical_work_id:, attempt_no:, runtime_execution_id:)
          synchronize do
            entries[agent_task_run_id] ||= Entry.new(
              agent_task_run_id: agent_task_run_id,
              logical_work_id: logical_work_id,
              attempt_no: attempt_no,
              runtime_execution_id: runtime_execution_id
            )
          end
        end

        def lookup(agent_task_run_id:)
          synchronize do
            entries[agent_task_run_id]
          end
        end

        def release(agent_task_run_id:)
          synchronize do
            entries.delete(agent_task_run_id)
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
