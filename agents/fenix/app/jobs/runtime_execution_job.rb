class RuntimeExecutionJob < ApplicationJob
  queue_as :default

  def perform(runtime_execution_id)
    runtime_execution = RuntimeExecution.find(runtime_execution_id)

    runtime_execution.with_lock do
      return unless runtime_execution.queued?

      runtime_execution.update!(status: "running", started_at: runtime_execution.started_at || Time.current)
    end

    result = Fenix::Runtime::ExecuteAssignment.call(
      mailbox_item: runtime_execution.mailbox_item_payload
    )

    runtime_execution.update!(
      status: result.status,
      reports: result.reports,
      trace: result.trace,
      output_payload: result.output,
      error_payload: result.error,
      finished_at: Time.current
    )
  rescue StandardError => error
    runtime_execution.update!(
      status: "failed",
      reports: runtime_execution.reports,
      trace: runtime_execution.trace,
      error_payload: {
        "failure_kind" => "job_error",
        "last_error_summary" => error.message,
      },
      finished_at: Time.current
    )
    raise
  end
end
