require "test_helper"

class AgentControlReportReceiptTest < ActiveSupport::TestCase
  test "requires protocol ids to be unique per installation and payloads to stay hashes" do
    context = build_agent_control_context!
    scenario = MailboxScenarioBuilder.new(self).execution_assignment!(context: context)
    receipt = AgentControlReportReceipt.create!(
      installation: context[:installation],
      agent_deployment: context[:deployment],
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
end
