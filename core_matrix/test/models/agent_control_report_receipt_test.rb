require "test_helper"

class AgentControlReportReceiptTest < ActiveSupport::TestCase
  test "requires protocol ids to be unique per installation and payloads to stay hashes" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    receipt = AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_session: context[:agent_session],
      agent_task_run: scenario.fetch(:agent_task_run),
      mailbox_item: scenario.fetch(:mailbox_item),
      protocol_message_id: "receipt-#{next_test_sequence}",
      method_id: "execution_started",
      result_code: "accepted",
      payload: { "mailbox_item_id" => scenario.fetch(:mailbox_item).public_id }
    )

    duplicate = receipt.dup
    duplicate.payload = "invalid"

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:protocol_message_id], "has already been taken"
    assert_includes duplicate.errors[:payload], "must be a hash"
  end

  test "stores only the report body and reconstructs structured control fields on read" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    mailbox_item = scenario.fetch(:mailbox_item)
    agent_task_run = scenario.fetch(:agent_task_run)

    receipt = AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_session: context[:agent_session],
      agent_task_run: agent_task_run,
      mailbox_item: mailbox_item,
      protocol_message_id: "receipt-compact-#{next_test_sequence}",
      method_id: "agent_program_completed",
      logical_work_id: agent_task_run.logical_work_id,
      attempt_no: agent_task_run.attempt_no,
      result_code: "accepted",
      payload: {
        "protocol_message_id" => "ignored-by-storage",
        "method_id" => "ignored-by-storage",
        "logical_work_id" => "ignored-by-storage",
        "attempt_no" => 99,
        "mailbox_item_id" => "ignored-by-storage",
        "runtime_plane" => "ignored-by-storage",
        "request_kind" => "ignored-by-storage",
        "control" => {
          "mailbox_item_id" => mailbox_item.public_id,
          "runtime_plane" => mailbox_item.runtime_plane,
          "request_kind" => mailbox_item.payload.fetch("request_kind"),
        },
        "response_payload" => { "content" => "ok" },
      }
    )

    stored_payload = receipt.report_document.payload

    refute stored_payload.key?("protocol_message_id")
    refute stored_payload.key?("method_id")
    refute stored_payload.key?("logical_work_id")
    refute stored_payload.key?("attempt_no")
    refute stored_payload.key?("mailbox_item_id")
    refute stored_payload.key?("runtime_plane")
    refute stored_payload.key?("request_kind")
    refute stored_payload.key?("control")
    assert_equal({ "content" => "ok" }, stored_payload.fetch("response_payload"))

    payload = receipt.payload

    assert_equal receipt.protocol_message_id, payload.fetch("protocol_message_id")
    assert_equal receipt.method_id, payload.fetch("method_id")
    assert_equal receipt.logical_work_id, payload.fetch("logical_work_id")
    assert_equal receipt.attempt_no, payload.fetch("attempt_no")
    assert_equal mailbox_item.public_id, payload.fetch("mailbox_item_id")
    assert_equal mailbox_item.runtime_plane, payload.fetch("runtime_plane")
    assert_equal mailbox_item.payload.fetch("request_kind"), payload.fetch("request_kind")
    assert_equal agent_task_run.conversation.public_id, payload.fetch("conversation_id")
    assert_equal agent_task_run.turn.public_id, payload.fetch("turn_id")
    assert_equal agent_task_run.workflow_node.public_id, payload.fetch("workflow_node_id")
    assert_equal({ "content" => "ok" }, payload.fetch("response_payload"))
  end
end
