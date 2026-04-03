class RuntimeExecutionJob < ApplicationJob
  queue_as :runtime_control

  def perform(runtime_execution_id, deliver_reports: false)
    runtime_execution = RuntimeExecution.find(runtime_execution_id)
    attempt = nil

    runtime_execution.with_lock do
      runtime_execution.reload
      return if runtime_execution.canceled?
      return unless runtime_execution.queued?

      runtime_execution.update!(status: "running", started_at: runtime_execution.started_at || Time.current)
    end

    attempt = Fenix::Runtime::ExecutionAttempt.new(
      agent_task_run_id: runtime_execution.agent_task_run_id,
      logical_work_id: runtime_execution.logical_work_id,
      attempt_no: runtime_execution.attempt_no,
      runtime_execution_id: runtime_execution.id
    )

    result = Fenix::Runtime::ExecuteMailboxItem.call(
      mailbox_item: runtime_execution.to_mailbox_item,
      attempt: attempt,
      cancellation_probe: -> { RuntimeExecution.where(id: runtime_execution.id, status: "canceled").exists? },
      on_report: ->(report) { append_report!(runtime_execution_id:, report:, deliver_reports:) }
    )

    persist_terminal_result!(runtime_execution:, result:)
  rescue StandardError => error
    runtime_execution.reload
    return if runtime_execution.canceled?

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
  ensure
  end

  private

  def append_report!(runtime_execution_id:, report:, deliver_reports:)
    runtime_execution = RuntimeExecution.find(runtime_execution_id)

    runtime_execution.with_lock do
      runtime_execution.reload
      return if runtime_execution.canceled?

      runtime_execution.update!(reports: runtime_execution.reports + [sanitize_report_for_persistence(report)])
    end

    Fenix::Runtime::ControlPlane.report!(payload: report) if deliver_reports
  end

  def persist_terminal_result!(runtime_execution:, result:)
    runtime_execution.with_lock do
      runtime_execution.reload
      return if runtime_execution.canceled?

      runtime_execution.update!(
        status: result.status,
        reports: result.reports.map { |report| sanitize_report_for_persistence(report) },
        trace: sanitize_json_value(result.trace),
        output_payload: sanitize_json_value(result.output),
        error_payload: sanitize_json_value(result.error),
        finished_at: Time.current
      )
    end
  end

  def sanitize_report_for_persistence(report)
    report = sanitize_json_value(report.deep_dup)
    tool_output = report.dig("progress_payload", "tool_invocation_output")
    return report if tool_output.blank? || !tool_output.key?("output_chunks")

    output_chunks = Array(tool_output.delete("output_chunks"))
    stream_bytes = output_chunks.each_with_object(Hash.new(0)) do |chunk, counts|
      counts[chunk["stream"].to_s] += chunk["text"].to_s.bytesize
    end

    tool_output["output_chunk_count"] = output_chunks.size
    tool_output["output_byte_count"] = stream_bytes.values.sum
    tool_output["output_streams"] = stream_bytes.keys.sort
    tool_output["stream_byte_count"] = stream_bytes
    report
  end

  def sanitize_json_value(value)
    case value
    when Hash
      value.transform_values { |entry| sanitize_json_value(entry) }
    when Array
      value.map { |entry| sanitize_json_value(entry) }
    when String
      sanitized = value.dup.force_encoding(Encoding::UTF_8)
      sanitized.valid_encoding? ? sanitized : sanitized.scrub
    else
      value
    end
  end
end
