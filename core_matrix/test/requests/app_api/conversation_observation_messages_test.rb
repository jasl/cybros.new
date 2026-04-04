require "test_helper"

class AppApiConversationObservationMessagesTest < ActionDispatch::IntegrationTest
  test "posting a message persists a frame-backed exchange and listing returns session history only" do
    fixture = build_observation_fixture!
    registration = register_machine_api_for_context!(fixture)
    transcript_count = fixture.fetch(:conversation).messages.count

    post "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).public_id}/messages",
      params: {
        content: "Summarize current progress for supervisor_status",
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
    assert_equal "user", response_body.dig("user_message", "role")
    assert_equal "observer_agent", response_body.dig("observer_message", "role")

    get "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).public_id}/messages",
      headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_observation_message_list", response_body.fetch("method_id")
    assert_equal fixture.fetch(:session).public_id, response_body.fetch("observation_session_id")
    assert_equal %w[user observer_agent], response_body.fetch("items").map { |item| item.fetch("role") }
  end

  test "rejects raw bigint session identifiers for create and list" do
    fixture = build_observation_fixture!
    registration = register_machine_api_for_context!(fixture)

    post "/app_api/conversation_observation_sessions/#{fixture.fetch(:session).id}/messages",
      params: {
        content: "Summarize current progress for supervisor_status",
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

    context.merge(
      conversation: conversation,
      current_turn: current_turn,
      workflow_run: workflow_run,
      workflow_node: workflow_node,
      session: session
    )
  end
end
