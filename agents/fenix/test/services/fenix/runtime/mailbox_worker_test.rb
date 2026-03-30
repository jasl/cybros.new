require "test_helper"
require "open3"

class Fenix::Runtime::MailboxWorkerTest < ActiveSupport::TestCase
  test "execution assignments create one durable runtime attempt and enqueue it once" do
    mailbox_item = runtime_assignment_payload(mode: "deterministic_tool").merge(
      "item_type" => "execution_assignment"
    )

    runtime_execution = nil

    assert_enqueued_jobs 1 do
      runtime_execution = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
    end

    assert_instance_of RuntimeExecution, runtime_execution
    assert_equal "queued", runtime_execution.status
    assert_equal mailbox_item.fetch("item_id"), runtime_execution.mailbox_item_id
    assert_equal mailbox_item.fetch("protocol_message_id"), runtime_execution.protocol_message_id
    assert_equal mailbox_item.fetch("logical_work_id"), runtime_execution.logical_work_id
    assert_equal mailbox_item.fetch("attempt_no"), runtime_execution.attempt_no
    assert_equal mailbox_item.fetch("runtime_plane"), runtime_execution.runtime_plane
    assert_equal mailbox_item, runtime_execution.mailbox_item_payload

    assert_enqueued_jobs 0 do
      duplicate = Fenix::Runtime::MailboxWorker.call(mailbox_item: mailbox_item)
      assert_equal runtime_execution.id, duplicate.id
    end
  end

  test "agent task close requests terminate attached command sessions and release the active attempt" do
    agent_task_run_id = "task-#{SecureRandom.uuid}"
    stdin = nil
    stdout = nil
    stderr = nil
    wait_thread = nil

    begin
      stdin, stdout, stderr, wait_thread = Open3.popen3("/bin/sh", "-lc", "cat")

      session = Fenix::Runtime::AttachedCommandSessionRegistry.register(
        agent_task_run_id: agent_task_run_id,
        stdin: stdin,
        stdout: stdout,
        stderr: stderr,
        wait_thread: wait_thread
      )
      Fenix::Runtime::AttemptRegistry.register(
        agent_task_run_id: agent_task_run_id,
        logical_work_id: "logical-work-1",
        attempt_no: 1,
        runtime_execution_id: 123
      )

      result = nil

      assert_enqueued_jobs 0 do
        result = Fenix::Runtime::MailboxWorker.call(
          mailbox_item: {
            "item_type" => "resource_close_request",
            "payload" => {
              "resource_type" => "AgentTaskRun",
              "resource_id" => agent_task_run_id,
            },
          }
        )
      end

      assert_equal :handled, result
      assert_nil Fenix::Runtime::AttemptRegistry.lookup(agent_task_run_id: agent_task_run_id)
      assert_nil Fenix::Runtime::AttachedCommandSessionRegistry.lookup(session_id: session.session_id)
      refute wait_thread.alive?
    ensure
      stdin&.close unless stdin.nil? || stdin.closed?
      stdout&.close unless stdout.nil? || stdout.closed?
      stderr&.close unless stderr.nil? || stderr.closed?
      Process.kill("KILL", wait_thread.pid) if wait_thread&.alive?
    end
  rescue Errno::ESRCH
    nil
  end
end
