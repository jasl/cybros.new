require "test_helper"

class EmbeddedAgents::ConversationSupervision::BuildSnapshotTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "freezes supervision state policy context feed and authority without storing raw transcript text" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
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
    assert_equal %w[active_subagent_turn_todo_plan_views active_subagents activity_feed capability_authority conversation_context_view primary_turn_todo_plan_view proof_debug turn_feed],
      bundle.keys.sort
    assert_equal "Rebuild the supervision sidechat surface",
      snapshot.machine_status_payload.fetch("request_summary")
    assert_equal "waiting", snapshot.machine_status_payload.fetch("overall_state")
    assert_equal "handoff", snapshot.machine_status_payload.fetch("board_lane")
    assert_equal true, bundle.dig("capability_authority", "supervision_enabled")
    assert_equal true, bundle.dig("capability_authority", "detailed_progress_enabled")
    assert_equal false, bundle.dig("capability_authority", "control_enabled")
    assert_equal [], bundle.dig("capability_authority", "available_control_verbs")
    assert_equal ["Freeze the supervision snapshot", "Rendering the frozen supervision snapshot"],
      bundle.fetch("primary_turn_todo_plan_view").fetch("items").map { |item| item.fetch("title") }
    assert_equal ["Checking the 2048 acceptance flow"],
      bundle.fetch("active_subagent_turn_todo_plan_views").map { |item| item.dig("current_item", "title") }
    assert_equal ["Checking the 2048 acceptance flow"],
      bundle.fetch("active_subagents").map { |item| item.fetch("current_focus_summary") }
    assert_nil snapshot.machine_status_payload["active_plan_items"]
    assert_includes bundle.dig("proof_debug", "feed_event_kinds"), "waiting_started"
    assert bundle.dig("conversation_context_view", "context_snippets").any? do |snippet|
      snippet.fetch("excerpt").match?(/adding tests|2048 acceptance flow/i)
    end
    refute_includes bundle.dig("conversation_context_view", "context_snippets").to_json,
      "Context already references"
    refute_includes bundle.to_json, "We already agreed to add tests before refactoring."
    refute_includes bundle.to_json, "The 2048 acceptance flow is already wired."
  end

  test "omits detailed progress artifacts when the conversation is configured for coarse supervision only" do
    fixture = prepare_conversation_supervision_context!(detailed_progress_enabled: false)
    session = create_conversation_supervision_session!(fixture)

    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    bundle = snapshot.bundle_payload

    assert_equal false, bundle.dig("capability_authority", "detailed_progress_enabled")
    assert_empty bundle.fetch("activity_feed")
    assert_empty bundle.dig("conversation_context_view", "context_snippets")
    assert_nil snapshot.machine_status_payload["request_summary"]
    assert_nil snapshot.machine_status_payload["current_focus_summary"]
    assert_nil snapshot.machine_status_payload["recent_progress_summary"]
    assert_nil snapshot.machine_status_payload["next_step_hint"]
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

  test "freezes turn todo plan views and turn feed in the snapshot bundle" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    session = create_conversation_supervision_session!(fixture)

    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    bundle = snapshot.bundle_payload

    assert_equal "render-snapshot", bundle.fetch("primary_turn_todo_plan_view").fetch("current_item_key")
    assert_equal ["check-hard-gate"],
      bundle.fetch("active_subagent_turn_todo_plan_views").map { |entry| entry.fetch("current_item_key") }
    assert_equal bundle.fetch("turn_feed"), snapshot.machine_status_payload.fetch("turn_feed")
    assert_nil snapshot.machine_status_payload["active_plan_items"]
  end

  test "freezes fallback turn todo plan and canonical feed for provider-backed turns without an agent task run" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)

    snapshot = EmbeddedAgents::ConversationSupervision::BuildSnapshot.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session
    )

    bundle = snapshot.bundle_payload
    primary_turn_todo_plan_view = bundle.fetch("primary_turn_todo_plan_view")

    assert primary_turn_todo_plan_view.fetch("turn_todo_plan_id").present?
    assert primary_turn_todo_plan_view.fetch("current_item_key").present?
    assert primary_turn_todo_plan_view.dig("current_item", "title").present?
    assert_equal fixture.fetch(:turn).public_id, primary_turn_todo_plan_view.fetch("turn_id")
    assert_equal "Waiting for the test-and-build check in /workspace/game-2048",
      primary_turn_todo_plan_view.dig("current_item", "title")
    assert bundle.fetch("turn_feed").any? { |entry| entry.fetch("event_kind").start_with?("turn_todo_") }
    assert_equal primary_turn_todo_plan_view,
      snapshot.machine_status_payload.fetch("primary_turn_todo_plan_view")
    assert_equal(
      {
        "kind" => "command_wait",
        "summary" => "waiting for the test-and-build check in /workspace/game-2048",
        "command_run_public_id" => fixture.fetch(:active_command_run).public_id,
      },
      snapshot.machine_status_payload.fetch("runtime_focus_hint").slice("kind", "summary", "command_run_public_id")
    )
    assert_match(/test run|test-and-build check/i,
      snapshot.machine_status_payload.fetch("recent_progress_summary"))
    refute_match(/provider round|command_run_wait|exec_command/i, snapshot.machine_status_payload.to_json)
  end
end
