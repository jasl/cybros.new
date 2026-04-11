require "test_helper"

class SubagentConnections::ValidateAddressabilityTest < ActiveSupport::TestCase
  test "owner-addressable conversations only allow human senders" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )

    SubagentConnections::ValidateAddressability.call(
      conversation: conversation,
      sender_kind: "human",
      rejection_message: "must be owner_addressable"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::ValidateAddressability.call(
        conversation: conversation,
        sender_kind: "owner_agent",
        rejection_message: "must be owner_addressable"
      )
    end

    assert_includes error.record.errors[:addressability], "must be owner_addressable"
  end

  test "agent-addressable conversations allow agent senders and reject humans" do
    context = create_workspace_context!
    owner_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot]
    )
    conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_snapshot: context[:agent_snapshot],
      addressability: "agent_addressable"
    )

    SubagentConnections::ValidateAddressability.call(
      conversation: conversation,
      sender_kind: "owner_agent",
      rejection_message: "must be agent_addressable"
    )

    error = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentConnections::ValidateAddressability.call(
        conversation: conversation,
        sender_kind: "human",
        rejection_message: "must be agent_addressable"
      )
    end

    assert_includes error.record.errors[:addressability], "must be agent_addressable"
  end
end
