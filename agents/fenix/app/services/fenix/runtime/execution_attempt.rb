module Fenix
  module Runtime
    class ExecutionAttempt < Struct.new(
      :agent_task_run_id,
      :logical_work_id,
      :attempt_no,
      :runtime_execution_id,
      keyword_init: true
    )
    end
  end
end
