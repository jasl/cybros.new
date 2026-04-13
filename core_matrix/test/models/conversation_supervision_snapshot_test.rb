require "test_helper"

class ConversationSupervisionSnapshotTest < ActiveSupport::TestCase
  test "freezes supervision and capability public ids alongside compact bundle payloads" do
    assert_not_includes ConversationSupervisionSnapshot.attribute_names, "conversation_capability_policy_public_id"

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
      capability_policy_snapshot: {},
      last_snapshot_at: Time.current
    )
    state = ConversationSupervisionState.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      overall_state: "running",
      current_owner_kind: "agent_task_run",
      current_owner_public_id: "task_run_public_id",
      request_summary: "Refactor the supervision domain",
      current_focus_summary: "Renaming the observation aggregates",
      recent_progress_summary: "Finished the new model tests",
      waiting_summary: nil,
      blocked_summary: nil,
      next_step_hint: "Rewrite the schema and models",
      last_progress_at: Time.current,
      status_payload: { "conversation_id" => conversation.public_id }
    )

    snapshot = ConversationSupervisionSnapshot.create!(
      installation: context[:installation],
      target_conversation: conversation,
      user: conversation.user,
      workspace: conversation.workspace,
      agent: conversation.agent,
      user_id: conversation.user_id,
      workspace_id: conversation.workspace_id,
      agent_id: conversation.agent_id,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: state.public_id,
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 4,
      conversation_event_projection_sequence_snapshot: 9,
      active_workflow_run_public_id: "workflow_run_public_id",
      active_workflow_node_public_id: "workflow_node_public_id",
      active_subagent_connection_public_ids: ["subagent_public_id"],
      bundle_payload: { "proof" => { "conversation_id" => conversation.public_id } },
      machine_status_payload: { "board_lane" => "active" }
    )

    assert snapshot.public_id.present?
    assert_equal snapshot, ConversationSupervisionSnapshot.find_by_public_id!(snapshot.public_id)
    assert_equal state.public_id, snapshot.conversation_supervision_state_public_id
    refute_respond_to snapshot, :conversation_capability_policy_public_id
    assert_equal ["subagent_public_id"], snapshot.active_subagent_connection_public_ids
    assert_equal({ "proof" => { "conversation_id" => conversation.public_id } }, snapshot.bundle_payload)
    assert_equal({ "board_lane" => "active" }, snapshot.machine_status_payload)
  end

  test "requires target conversation to match the session" do
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

    snapshot = ConversationSupervisionSnapshot.new(
      installation: context[:installation],
      target_conversation: other_conversation,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:target_conversation], "must match the supervision session target conversation"
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
    foreign = create_workspace_context!

    snapshot = ConversationSupervisionSnapshot.new(
      installation: context[:installation],
      target_conversation: conversation,
      user_id: foreign[:user].id,
      workspace_id: foreign[:workspace].id,
      agent_id: foreign[:agent].id,
      conversation_supervision_session: session,
      conversation_supervision_state_public_id: "state_public_id",
      anchor_turn_public_id: "turn_public_id",
      anchor_turn_sequence_snapshot: 1,
      conversation_event_projection_sequence_snapshot: 1,
      active_subagent_connection_public_ids: [],
      bundle_payload: {},
      machine_status_payload: {}
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:user], "must match the target conversation user"
    assert_includes snapshot.errors[:workspace], "must match the target conversation workspace"
    assert_includes snapshot.errors[:agent], "must match the target conversation agent"
  end
end
