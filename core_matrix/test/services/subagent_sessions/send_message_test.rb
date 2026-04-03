require "test_helper"

class SubagentSessions::SendMessageTest < ActiveSupport::TestCase
  test "rejects senders other than owner agent subagent self and system" do
    context = create_workspace_context!
    root_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    child_conversation = create_agent_addressable_child_conversation!(
      context: context,
      owner_conversation: root_conversation
    )
    outsider_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )

    invalid_sender = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentSessions::SendMessage.call(
        conversation: child_conversation,
        content: "Blocked",
        sender_kind: "human"
      )
    end
    wrong_owner = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentSessions::SendMessage.call(
        conversation: child_conversation,
        content: "Blocked",
        sender_kind: "owner_agent",
        sender_conversation: outsider_conversation
      )
    end
    wrong_self = assert_raises(ActiveRecord::RecordInvalid) do
      SubagentSessions::SendMessage.call(
        conversation: child_conversation,
        content: "Blocked",
        sender_kind: "subagent_self",
        sender_conversation: root_conversation
      )
    end

    assert_includes invalid_sender.record.errors[:addressability], "must be agent_addressable for subagent delivery"
    assert_includes wrong_owner.record.errors[:sender_kind], "must match the owner conversation for owner_agent delivery"
    assert_includes wrong_self.record.errors[:sender_kind], "must match the target conversation for subagent_self delivery"
  end

  test "successful sends append transcript and project audit events" do
    context = create_workspace_context!
    root_conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    child_conversation = create_agent_addressable_child_conversation!(
      context: context,
      owner_conversation: root_conversation
    )

    owner_message = SubagentSessions::SendMessage.call(
      conversation: child_conversation,
      content: "Owner note",
      sender_kind: "owner_agent",
      sender_conversation: root_conversation
    )
    self_message = SubagentSessions::SendMessage.call(
      conversation: child_conversation,
      content: "Self note",
      sender_kind: "subagent_self",
      sender_conversation: child_conversation
    )
    system_message = SubagentSessions::SendMessage.call(
      conversation: child_conversation,
      content: "System note",
      sender_kind: "system"
    )

    assert_equal ["Owner note", "Self note", "System note"], child_conversation.messages.order(:id).pluck(:content)
    assert_equal [owner_message.public_id, self_message.public_id, system_message.public_id],
      child_conversation.messages.order(:id).pluck(:public_id)
    assert_equal ["subagent.message_appended"] * 3,
      ConversationEvent.where(conversation: child_conversation).order(:projection_sequence).pluck(:event_kind)
    assert_equal %w[owner_agent subagent_self system],
      ConversationEvent.where(conversation: child_conversation).order(:projection_sequence).map { |event| event.payload.fetch("sender_kind") }
    assert_equal owner_message, ConversationEvent.where(conversation: child_conversation).order(:projection_sequence).first.source
  end

  private

  def create_agent_addressable_child_conversation!(context:, owner_conversation:)
    child_conversation = create_conversation_record!(
      installation: context[:installation],
      workspace: context[:workspace],
      parent_conversation: owner_conversation,
      kind: "fork",
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version],
      addressability: "agent_addressable"
    )
    SubagentSession.create!(
      installation: context[:installation],
      conversation: child_conversation,
      owner_conversation: owner_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0
    )

    child_conversation
  end
end
