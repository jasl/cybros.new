require "test_helper"

class RuntimeExecutionJobTest < ActiveJob::TestCase
  test "does not re-execute an assignment that is already running" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-1",
      protocol_message_id: "protocol-message-1",
      logical_work_id: "logical-work-1",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "running",
      mailbox_item_payload: runtime_assignment_payload(mode: "deterministic_tool"),
      reports: [],
      trace: [],
      started_at: Time.current
    )

    execute_assignment_singleton = Fenix::Runtime::ExecuteAssignment.singleton_class
    original_execute_assignment = Fenix::Runtime::ExecuteAssignment.method(:call)
    calls = []

    execute_assignment_singleton.send(:define_method, :call) do |**kwargs|
      calls << kwargs
      raise "unexpected runtime execution"
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id)

    assert_empty calls
    assert_equal "running", runtime_execution.reload.status
  ensure
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "persists reports incrementally while the execution job is running" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-2",
      protocol_message_id: "protocol-message-2",
      logical_work_id: "logical-work-2",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "queued",
      mailbox_item_payload: runtime_assignment_payload(mode: "deterministic_tool"),
      reports: [],
      trace: []
    )

    execute_assignment_singleton = Fenix::Runtime::ExecuteAssignment.singleton_class
    original_execute_assignment = Fenix::Runtime::ExecuteAssignment.method(:call)
    snapshots = []

    execute_assignment_singleton.send(:define_method, :call) do |mailbox_item:, on_report: nil, attempt: nil, cancellation_probe: nil|
      started = { "method_id" => "execution_started" }
      progress = { "method_id" => "execution_progress" }
      completed = { "method_id" => "execution_complete" }

      on_report.call(started)
      snapshots << RuntimeExecution.find(runtime_execution.id).reports.map { |report| report.fetch("method_id") }
      on_report.call(progress)
      snapshots << RuntimeExecution.find(runtime_execution.id).reports.map { |report| report.fetch("method_id") }
      on_report.call(completed)
      snapshots << RuntimeExecution.find(runtime_execution.id).reports.map { |report| report.fetch("method_id") }

      Fenix::Runtime::ExecuteAssignment::Result.new(
        status: "completed",
        reports: [started, progress, completed],
        trace: [],
        output: "done"
      )
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id)

    assert_equal [%w[execution_started], %w[execution_started execution_progress], %w[execution_started execution_progress execution_complete]], snapshots
    assert_equal %w[execution_started execution_progress execution_complete], runtime_execution.reload.reports.map { |report| report.fetch("method_id") }
    assert_equal "completed", runtime_execution.status
  ensure
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "passes execution attempt metadata while the execution is running" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-3",
      protocol_message_id: "protocol-message-3",
      logical_work_id: "logical-work-3",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "queued",
      mailbox_item_payload: runtime_assignment_payload(mode: "deterministic_tool"),
      reports: [],
      trace: []
    )

    execute_assignment_singleton = Fenix::Runtime::ExecuteAssignment.singleton_class
    original_execute_assignment = Fenix::Runtime::ExecuteAssignment.method(:call)
    observed_attempt = nil
    execute_assignment_singleton.send(:define_method, :call) do |mailbox_item:, on_report: nil, attempt:, cancellation_probe: nil|
      observed_attempt = attempt

      Fenix::Runtime::ExecuteAssignment::Result.new(
        status: "completed",
        reports: [],
        trace: [],
        output: "done"
      )
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id)

    assert_equal runtime_execution.mailbox_item_payload.dig("payload", "agent_task_run_id"), observed_attempt.agent_task_run_id
    assert_equal runtime_execution.logical_work_id, observed_attempt.logical_work_id
    assert_equal runtime_execution.attempt_no, observed_attempt.attempt_no
    assert_equal runtime_execution.id, observed_attempt.runtime_execution_id
  ensure
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "keeps a runtime execution canceled when cancellation lands before terminal persistence" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-4",
      protocol_message_id: "protocol-message-4",
      logical_work_id: "logical-work-4",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "queued",
      mailbox_item_payload: runtime_assignment_payload(mode: "deterministic_tool"),
      reports: [],
      trace: []
    )

    execute_assignment_singleton = Fenix::Runtime::ExecuteAssignment.singleton_class
    original_execute_assignment = Fenix::Runtime::ExecuteAssignment.method(:call)

    execute_assignment_singleton.send(:define_method, :call) do |mailbox_item:, on_report: nil, attempt:, cancellation_probe: nil|
      runtime_execution.update_columns(
        status: "canceled",
        finished_at: Time.current,
        error_payload: {
          "failure_kind" => "canceled",
          "last_error_summary" => "execution canceled by close request",
        }
      )

      Fenix::Runtime::ExecuteAssignment::Result.new(
        status: "completed",
        reports: [],
        trace: [],
        output: "done"
      )
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id)

    runtime_execution.reload
    assert_equal "canceled", runtime_execution.status
    assert_equal "canceled", runtime_execution.error_payload.fetch("failure_kind")
  ensure
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "persists streamed tool output as summary-only while still delivering live chunks" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-4b",
      protocol_message_id: "protocol-message-4b",
      logical_work_id: "logical-work-4b",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "queued",
      mailbox_item_payload: runtime_assignment_payload(mode: "deterministic_tool"),
      reports: [],
      trace: []
    )

    execute_assignment_singleton = Fenix::Runtime::ExecuteAssignment.singleton_class
    original_execute_assignment = Fenix::Runtime::ExecuteAssignment.method(:call)
    streamed_progress = {
      "method_id" => "execution_progress",
      "progress_payload" => {
        "stage" => "tool_output",
        "tool_invocation_output" => {
          "tool_invocation_id" => "tool-invocation-1",
          "call_id" => "tool-call-1",
          "tool_name" => "exec_command",
          "command_run_id" => "command-run-1",
          "output_chunks" => [
            { "stream" => "stdout", "text" => "hello\n" },
            { "stream" => "stderr", "text" => "warn\n" },
          ],
        },
      },
    }

    execute_assignment_singleton.send(:define_method, :call) do |mailbox_item:, on_report: nil, attempt:, cancellation_probe: nil|
      started = { "method_id" => "execution_started" }
      completed = { "method_id" => "execution_complete", "terminal_payload" => { "output" => "done" } }

      on_report.call(started)
      on_report.call(streamed_progress)
      on_report.call(completed)

      Fenix::Runtime::ExecuteAssignment::Result.new(
        status: "completed",
        reports: [started, streamed_progress, completed],
        trace: [],
        output: "done"
      )
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id, deliver_reports: true)

    persisted_output = runtime_execution.reload.reports.second.fetch("progress_payload").fetch("tool_invocation_output")
    delivered_output = Fenix::Runtime::ControlPlane.client.reported_payloads.second.fetch("progress_payload").fetch("tool_invocation_output")

    refute persisted_output.key?("output_chunks")
    assert_equal 2, persisted_output.fetch("output_chunk_count")
    assert_equal 11, persisted_output.fetch("output_byte_count")
    assert_equal %w[stderr stdout], persisted_output.fetch("output_streams")
    assert_equal({ "stderr" => 5, "stdout" => 6 }, persisted_output.fetch("stream_byte_count"))

    assert_equal streamed_progress.dig("progress_payload", "tool_invocation_output", "output_chunks"),
      delivered_output.fetch("output_chunks")
  ensure
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "does not provision tool side effects after cancellation lands during tool review" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-5",
      protocol_message_id: "protocol-message-5",
      logical_work_id: "logical-work-5",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "queued",
      mailbox_item_payload: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "exec_command",
          "command_line" => "printf 'hello\\n'",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + %w[exec_command write_stdin]
        )
      ),
      reports: [],
      trace: []
    )

    review_tool_call_singleton = Fenix::Hooks::ReviewToolCall.singleton_class
    original_review_tool_call = Fenix::Hooks::ReviewToolCall.method(:call)

    review_tool_call_singleton.send(:define_method, :call) do |**kwargs|
      reviewed = original_review_tool_call.call(**kwargs)
      runtime_execution.cancel!(request_kind: "turn_interrupt", reason_kind: "operator_requested", occurred_at: Time.current)
      reviewed
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id)

    assert_equal "canceled", runtime_execution.reload.status
    assert_empty Fenix::Runtime::ControlPlane.client.tool_invocation_requests
    assert_empty Fenix::Runtime::ControlPlane.client.command_run_requests
  ensure
    review_tool_call_singleton.send(:define_method, :call, original_review_tool_call) if review_tool_call_singleton && original_review_tool_call
  end

  test "reports a synthetic process exit when cancellation lands after process provisioning but before spawn" do
    runtime_execution = RuntimeExecution.create!(
      mailbox_item_id: "mailbox-item-6",
      protocol_message_id: "protocol-message-6",
      logical_work_id: "logical-work-6",
      attempt_no: 1,
      runtime_plane: "agent",
      status: "queued",
      mailbox_item_payload: runtime_assignment_payload(
        mode: "deterministic_tool",
        task_payload: {
          "tool_name" => "process_exec",
          "command_line" => "sleep 1",
          "kind" => "background_service",
        },
        agent_context: default_agent_context.merge(
          "allowed_tool_names" => default_agent_context.fetch("allowed_tool_names") + ["process_exec"]
        )
      ),
      reports: [],
      trace: []
    )

    control_client = Fenix::Runtime::ControlPlane.client
    original_create_process_run = control_client.method(:create_process_run!)

    control_client.define_singleton_method(:create_process_run!) do |**kwargs|
      response = original_create_process_run.call(**kwargs)
      runtime_execution.cancel!(request_kind: "turn_interrupt", reason_kind: "operator_requested", occurred_at: Time.current)
      response
    end

    RuntimeExecutionJob.perform_now(runtime_execution.id)

    runtime_execution.reload
    assert_equal "canceled", runtime_execution.status
    assert_equal 1, control_client.process_run_requests.size
    assert_nil Fenix::Processes::Manager.lookup(
      process_run_id: control_client.process_run_requests.first.dig("response", "process_run_id")
    )

    started_reports = control_client.reported_payloads.select { |payload| payload["method_id"] == "process_started" }
    assert_empty started_reports

    exited_report = control_client.reported_payloads.find { |payload| payload["method_id"] == "process_exited" }
    assert_not_nil exited_report
    assert_equal "stopped", exited_report.fetch("lifecycle_state")
    assert_equal "canceled_before_start", exited_report.dig("metadata", "reason")
  ensure
    control_client.define_singleton_method(:create_process_run!, original_create_process_run) if control_client && original_create_process_run
  end
end
