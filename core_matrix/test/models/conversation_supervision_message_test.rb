require "test_helper"

class ConversationSupervisionMessageTest < ActiveSupport::TestCase
  test "supports side chat roles on supervision snapshots without mutating the target transcript" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true },
      last_snapshot_at: Time.current
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      conversation_capability_policy_public_id: "policy_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )

    transcript_count = Message.where(conversation: conversation).count

    user_message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "user",
      content: "What are you doing now?"
    )
    supervisor_message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "supervisor_agent",
      content: "I am rewriting the supervision schema."
    )
    system_message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "system",
      content: "Side chat note"
    )

    assert_equal [user_message, supervisor_message, system_message], ConversationSupervisionMessage.order(:id)
    assert_equal "supervisor_agent", supervisor_message.role
    assert_equal transcript_count, Message.where(conversation: conversation).count
  end

  test "requires the message to stay on the supervision session target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    other_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      conversation_capability_policy_public_id: "policy_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )

    message = ConversationSupervisionMessage.new(
      installation: context[:installation],
      target_conversation: other_conversation,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "user",
      content: "Mismatch"
    )

    assert_not message.valid?
    assert_includes message.errors[:target_conversation], "must match the supervision session target conversation"
  end

  test "requires duplicated owner context to match the target conversation" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      execution_runtime: context[:execution_runtime],
      agent: context[:agent]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      conversation_capability_policy_public_id: "policy_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )
    foreign = create_workspace_context!

    message = ConversationSupervisionMessage.new(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "user",
      content: "Mismatch"
    )

    assert_not message.valid?
    assert_includes message.errors[:user], "must match the target conversation user"
    assert_includes message.errors[:workspace], "must match the target conversation workspace"
    assert_includes message.errors[:agent], "must match the target conversation agent"
  end
end
