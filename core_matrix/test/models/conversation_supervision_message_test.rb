require "test_helper"

class ConversationSupervisionMessageTest < ActiveSupport::TestCase
  test "supports side chat roles on supervision snapshots without mutating the target transcript" do
    context = create_workspace_context!
    conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      executor_program: context[:executor_program],
      agent_program: context[:agent_program]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "supervision_enabled" => true },
      last_snapshot_at: Time.current
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      conversation_capability_policy_public_id: "policy_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_session_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )

    transcript_count = Message.where(conversation: conversation).count

    user_message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "user",
      content: "What are you doing now?"
    )
    supervisor_message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_snapshot: snapshot,
      role: "supervisor_agent",
      content: "I am rewriting the supervision schema."
    )
    system_message = ConversationSupervisionMessage.create!(
      installation: context[:installation],
      target_conversation: conversation,
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
      executor_program: context[:executor_program],
      agent_program: context[:agent_program]
    )
    other_conversation = create_conversation_record!(
      workspace: context[:workspace],
      installation: context[:installation],
      executor_program: context[:executor_program],
      agent_program: context[:agent_program]
    )
    session = ConversationSupervisionSession.create!(
      installation: context[:installation],
      target_conversation: conversation,
      initiator: context[:user],
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      conversation_capability_policy_public_id: "policy_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_session_public_ids: [],
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
end
