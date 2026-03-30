require "test_helper"

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
end
