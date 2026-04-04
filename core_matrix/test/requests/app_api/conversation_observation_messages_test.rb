require "test_helper"

class AppApiConversationObservationMessagesTest < ActionDispatch::IntegrationTest
  test "posting a message persists a frame-backed exchange and listing returns session history only" do
    fixture = build_observation_fixture!
    registration = register_machine_api_for_context!(fixture)
    transcript_count = fixture.fetch(:conversation).messages.count

    post "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).public_id}/messages",
      params: {
        content: "What changed most recently?",
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :created
    assert_equal transcript_count, fixture.fetch(:conversation).reload.messages.count

    response_body = JSON.parse(response.body)
    assert_equal "conversation_observation_message_create", response_body.fetch("method_id")
    assert_equal fixture.fetch(:session).public_id, response_body.fetch("observation_session_id")
    assert_equal "waiting", response_body.dig("supervisor_status", "overall_state")
    assert_equal response_body.dig("assessment", "proof_refs"), response_body.dig("human_sidechat", "proof_refs")
    assert_equal response_body.dig("assessment", "proof_refs"), response_body.dig("supervisor_status", "proof_refs")
    assert_match(/Since the last observation|The most recent durable change/, response_body.dig("human_sidechat", "content"))
    refute_match(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/, response_body.dig("human_sidechat", "content"))
    assert_equal "user", response_body.dig("user_message", "role")
    assert_equal "observer_agent", response_body.dig("observer_message", "role")

    get "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).public_id}/messages",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_observation_message_list", response_body.fetch("method_id")
    assert_equal fixture.fetch(:session).public_id, response_body.fetch("observation_session_id")
    assert_equal %w[observer_agent user observer_agent], response_body.fetch("items").map { |item| item.fetch("role") }
    assert_equal "Previous summary", response_body.fetch("items").first.fetch("content")
    assert_equal "What changed most recently?", response_body.fetch("items")[-2].fetch("content")
  end

  test "rejects raw bigint session identifiers for create and list" do
    fixture = build_observation_fixture!
    registration = register_machine_api_for_context!(fixture)

    post "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).id}/messages",
      params: {
        content: "What changed most recently?",
      },
      headers: app_api_headers(registration[:machine_credential]),
      as: :json

    assert_response :not_found

    get "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).id}/messages",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  end

  private

  def build_observation_fixture!
    context = build_canonical_variable_context!
    conversation = context.fetch(:conversation)
    attach_selected_output!(context.fetch(:turn), content: "Earlier answer")
    context.fetch(:turn).update!(lifecycle_state: "completed")
    context.fetch(:workflow_run).update!(lifecycle_state: "completed")

    current_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Current progress update?",
      agent_program_version: context.fetch(:agent_program_version),
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    workflow_run = create_workflow_run!(turn: current_turn, wait_state: "ready", wait_reason_payload: {})
    workflow_node = create_workflow_node!(
      workflow_run: workflow_run,
      node_key: "implement",
      node_type: "turn_step",
      lifecycle_state: "running",
      presentation_policy: "ops_trackable",
      decision_source: "agent_program",
      started_at: 2.minutes.ago,
      metadata: {}
    )
    child_conversation = create_conversation_record!(
      installation: context.fetch(:installation),
      workspace: context.fetch(:workspace),
      parent_conversation: conversation,
      kind: "fork",
      execution_runtime: context.fetch(:execution_runtime),
      agent_program_version: context.fetch(:agent_program_version),
      addressability: "agent_addressable"
    )
    subagent_session = SubagentSession.create!(
      installation: context.fetch(:installation),
      owner_conversation: conversation,
      conversation: child_conversation,
      scope: "conversation",
      profile_key: "researcher",
      depth: 0,
      observed_status: "running"
    )
    workflow_run.update!(
      wait_state: "waiting",
      wait_reason_kind: "subagent_barrier",
      wait_reason_payload: { "subagent_session_ids" => [subagent_session.public_id] },
      waiting_since_at: 1.minute.ago
    )
    ConversationRuntime::PublishEvent.call(
      conversation: conversation,
      turn: current_turn,
      event_kind: "runtime.workflow_node.started",
      payload: {
        "workflow_run_id" => workflow_run.public_id,
        "workflow_node_id" => workflow_node.public_id,
        "state" => "running",
      }
    )

    session = ConversationObservationSession.create!(
      installation: context.fetch(:installation),
      target_conversation: conversation,
      initiator: context.fetch(:user),
      lifecycle_state: "open",
      responder_strategy: "builtin",
      capability_policy_snapshot: { "observe" => true, "control_enabled" => false }
    )
    session.conversation_observation_frames.create!(
      installation: context.fetch(:installation),
      target_conversation: conversation,
      anchor_turn_public_id: current_turn.public_id,
      anchor_turn_sequence_snapshot: current_turn.sequence,
      conversation_event_projection_sequence_snapshot: ConversationEvent.where(conversation: conversation).maximum(:projection_sequence),
      active_workflow_run_public_id: workflow_run.public_id,
      active_workflow_node_public_id: workflow_node.public_id,
      wait_state: workflow_run.wait_state,
      wait_reason_kind: workflow_run.wait_reason_kind,
      active_subagent_session_public_ids: [subagent_session.public_id],
      runtime_state_snapshot: {},
      bundle_snapshot: {
        "transcript_view" => { "conversation_id" => conversation.public_id, "anchor_turn_id" => current_turn.public_id, "messages" => [] },
        "workflow_view" => { "conversation_id" => conversation.public_id, "workflow_run_id" => workflow_run.public_id, "workflow_node_id" => workflow_node.public_id, "workflow_lifecycle_state" => workflow_run.lifecycle_state, "wait_state" => workflow_run.wait_state, "wait_reason_kind" => workflow_run.wait_reason_kind, "node_key" => workflow_node.node_key, "node_type" => workflow_node.node_type, "node_lifecycle_state" => workflow_node.lifecycle_state, "node_started_at" => workflow_node.started_at.iso8601(6) },
        "activity_view" => { "conversation_id" => conversation.public_id, "latest_projection_sequence" => 1, "items" => [{ "projection_sequence" => 1, "event_kind" => "runtime.workflow_node.started", "payload" => { "workflow_run_id" => workflow_run.public_id }, "created_at" => Time.current.iso8601(6) }] },
        "subagent_view" => { "conversation_id" => conversation.public_id, "items" => [{ "subagent_session_id" => subagent_session.public_id, "conversation_id" => child_conversation.public_id, "scope" => subagent_session.scope, "profile_key" => subagent_session.profile_key, "observed_status" => subagent_session.observed_status, "derived_close_status" => subagent_session.derived_close_status, "depth" => subagent_session.depth }] },
        "diagnostic_view" => { "conversation_id" => conversation.public_id, "lifecycle_state" => conversation.lifecycle_state, "turn_count" => 2, "active_turn_count" => 1, "completed_turn_count" => 1, "failed_turn_count" => 0, "provider_round_count" => 0, "tool_call_count" => 0, "tool_failure_count" => 0, "command_run_count" => 0, "command_failure_count" => 0, "process_run_count" => 0, "process_failure_count" => 0, "subagent_session_count" => 1, "estimated_cost_total" => "0.0", "outlier_refs" => {}, "cost_summary" => {}, "tool_breakdown" => {}, "subagent_status_counts" => {} },
        "memory_view" => {},
      },
      assessment_payload: {}
    )
    session.conversation_observation_messages.create!(
      installation: context.fetch(:installation),
      target_conversation: conversation,
      conversation_observation_frame: session.conversation_observation_frames.last,
      role: "observer_agent",
      content: "Previous summary",
      metadata: {
        "supervisor_status" => {
          "overall_state" => "running",
          "current_activity" => "Running provider_round_1 (queued)",
          "recent_activity_items" => [{ "projection_sequence" => 1, "event_kind" => "runtime.workflow_node.started" }],
          "transcript_refs" => [],
        },
      }
    )

    context.merge(
      conversation: conversation,
      current_turn: current_turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      session: session
    )
  end
end
