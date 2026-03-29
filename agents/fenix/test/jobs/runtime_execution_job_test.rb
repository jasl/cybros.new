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
end
