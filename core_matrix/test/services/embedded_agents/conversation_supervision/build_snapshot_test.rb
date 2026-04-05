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
end
