require "test_helper"

class EmbeddedAgents::ConversationSupervision::BuildSnapshotTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "freezes supervision state policy context feed and authority without storing raw transcript text" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)

    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    assert_equal fixture.fetch(:conversation).conversation_supervision_state.public_id,
      snapshot.conversation_supervision_state_public_id
    assert_equal fixture.fetch(:policy).public_id,
      snapshot.conversation_capability_policy_public_id
    assert_equal fixture.fetch(:current_turn).public_id, snapshot.anchor_turn_public_id
    assert_equal [fixture.fetch(:subagent_session).public_id], snapshot.active_subagent_session_public_ids

    bundle = snapshot.bundle_payload
    assert_equal %w[active_plan_items active_subagents activity_feed capability_authority conversation_context_view proof_debug],
      bundle.keys.sort
    assert_equal "Rebuild the supervision sidechat surface",
      snapshot.machine_status_payload.fetch("request_summary")
    assert_equal "waiting", snapshot.machine_status_payload.fetch("overall_state")
    assert_equal "handoff", snapshot.machine_status_payload.fetch("board_lane")
    assert_equal true, bundle.dig("capability_authority", "supervision_enabled")
    assert_equal false, bundle.dig("capability_authority", "control_enabled")
    assert_equal [], bundle.dig("capability_authority", "available_control_verbs")
    assert_equal ["Freeze the supervision snapshot", "Render the human supervisor reply"],
      bundle.fetch("active_plan_items").map { |item| item.fetch("title") }
    assert_equal ["Checking the 2048 acceptance flow"],
      bundle.fetch("active_subagents").map { |item| item.fetch("current_focus_summary") }
    assert_includes bundle.dig("proof_debug", "feed_event_kinds"), "waiting_started"
    assert_includes bundle.dig("conversation_context_view", "facts").map { |fact| fact.fetch("summary") },
      "Context already references adding tests."
    assert_includes bundle.dig("conversation_context_view", "facts").map { |fact| fact.fetch("summary") },
      "Context already references the 2048 acceptance flow."
    refute_includes bundle.to_json, "We already agreed to add tests before refactoring."
    refute_includes bundle.to_json, "The 2048 acceptance flow is already wired."
  end

  test "refreshes an existing supervision state before freezing the snapshot" do
    context = build_agent_control_context!
    policy = ConversationCapabilityPolicy.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      supervision_enabled: true,
      side_chat_enabled: true,
      control_enabled: false,
      policy_payload: {}
    )
    stale_state = Conversations::UpdateSupervisionState.call(
      conversation: context.fetch(:conversation),
      occurred_at: 2.minutes.ago
    )
    assert_equal "queued", stale_state.overall_state

    context.fetch(:workflow_node).update!(
      lifecycle_state: "completed",
      started_at: 90.seconds.ago,
      finished_at: 60.seconds.ago
    )
    create_workflow_node!(
      workflow_run: context.fetch(:workflow_run),
      installation: context.fetch(:installation),
      node_key: "provider_round_2",
      node_type: "turn_step",
      lifecycle_state: "running",
      started_at: 30.seconds.ago,
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      metadata: {}
    )
    session = ConversationSupervisionSession.create!(
      installation: context.fetch(:installation),
      target_conversation: context.fetch(:conversation),
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: supervision_policy_snapshot_for(policy)
    )

    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: context.fetch(:user),
      conversation_supervision_session: session
    )

    assert_equal "running", snapshot.machine_status_payload.fetch("overall_state")
    assert_equal "active", snapshot.machine_status_payload.fetch("board_lane")
    assert_equal "workflow_run", snapshot.machine_status_payload.fetch("current_owner_kind")
    assert_equal "running", context.fetch(:conversation).reload.conversation_supervision_state.overall_state
  end
end
