require "test_helper"

class SubagentConnections::ValidateAddressabilityTest < ActiveSupport::TestCase
  test "main transcript entry only allows human senders" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )

    SubagentConnections::ValidateAddressability.call(
      conversation: conversation,
      sender_kind: "human",
      rejection_message: "must allow main transcript entry"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::ValidateAddressability.call(
        conversation: conversation,
        sender_kind: "owner_agent",
        rejection_message: "must allow main transcript entry"
      )
    end

    assert_includes error.record.errors[:entry_policy_payload], "must allow main transcript entry"
  end

  test "agent internal conversations allow agent senders and reject humans" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version],
      entry_policy_payload: agent_internal_entry_policy_payload
    )

    SubagentConnections::ValidateAddressability.call(
      conversation: conversation,
      sender_kind: "owner_agent",
      rejection_message: "must allow agent internal entry"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::ValidateAddressability.call(
        conversation: conversation,
        sender_kind: "human",
        rejection_message: "must allow agent internal entry"
      )
    end

    assert_includes error.record.errors[:entry_policy_payload], "must allow agent internal entry"
  end
end
