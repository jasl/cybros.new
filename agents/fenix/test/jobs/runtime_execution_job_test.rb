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
    Fenix::Runtime::AttemptRegistry.reset!
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

    execute_assignment_singleton.send(:define_method, :call) do |mailbox_item:, on_report: nil, attempt: nil|
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
    Fenix::Runtime::AttemptRegistry.reset!
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end

  test "registers the active attempt while the execution is running and releases it afterward" do
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
    lookup_during_execution = nil

    execute_assignment_singleton.send(:define_method, :call) do |mailbox_item:, on_report: nil, attempt:|
      observed_attempt = attempt
      lookup_during_execution = Fenix::Runtime::AttemptRegistry.lookup(
        agent_task_run_id: mailbox_item.dig("payload", "agent_task_run_id")
      )

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
    assert_same observed_attempt, lookup_during_execution
    assert_nil Fenix::Runtime::AttemptRegistry.lookup(agent_task_run_id: observed_attempt.agent_task_run_id)
  ensure
    Fenix::Runtime::AttemptRegistry.reset!
    execute_assignment_singleton.send(:define_method, :call, original_execute_assignment) if execute_assignment_singleton && original_execute_assignment
  end
end
