require "test_helper"

class AgentControl::SerializeMailboxItemTest < ActiveSupport::TestCase
  test "serializes delivery fields with public ids and iso8601 timestamps" do
    context = build_agent_control_context!
    available_at = Time.zone.parse("2026-03-29 19:30:00 UTC")
    mailbox_item = create_agent_control_mailbox_item!(
      installation: context[:installation],
      target_agent_program: context[:agent_program],
      target_agent_program_version: context[:deployment],
      available_at: available_at,
      execution_hard_deadline_at: available_at + 5.minutes,
      payload: { "step" => "execute" }
    )

    serialized = AgentControl::SerializeMailboxItem.call(mailbox_item)

    assert_equal mailbox_item.public_id, serialized["item_id"]
    assert_equal context[:deployment].public_id, serialized["target_ref"]
    assert_equal available_at.iso8601, serialized["available_at"]
    assert_equal({ "step" => "execute" }, serialized["payload"])
    refute serialized.key?("id")
  end
end
