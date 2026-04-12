require "test_helper"

class AppApiConversationTurnRuntimeEventsControllerTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "lists the canonical turn runtime event stream for a conversation turn" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/turns/#{fixture.fetch(:turn).public_id}/runtime_events",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "conversation_turn_runtime_event_list", body.fetch("method_id")
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    assert_equal fixture.fetch(:turn).public_id, body.fetch("turn_id")
    assert_includes body.fetch("lanes").map { |lane| lane.fetch("actor_label") }, "main"

    summaries = body.fetch("items").map { |entry| entry.fetch("summary") }
    assert_includes summaries, "A shell command finished in /workspace/game-2048"
    assert_includes summaries, "A shell command is running in /workspace/game-2048"

    current_check = body.fetch("items").find do |entry|
      entry.fetch("summary") == "A shell command is running in /workspace/game-2048"
    end

    assert_equal fixture.fetch(:active_command_run).public_id, current_check.fetch("command_run_public_id")
    assert current_check.fetch("workflow_node_key").present?
    refute_includes response.body, %("#{fixture.fetch(:conversation).id}")
    refute_includes response.body, %("#{fixture.fetch(:turn).id}")
  end

  test "rejects raw bigint identifiers and turn ids outside the conversation" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)
    other_conversation = create_conversation_record!(
      workspace: fixture.fetch(:workspace),
      agent_definition_version: fixture.fetch(:agent_definition_version),
      execution_runtime: fixture.fetch(:execution_runtime)
    )
    other_turn = Turns::StartUserTurn.call(
      conversation: other_conversation,
      content: "Other conversation turn",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    get "/app_api/conversations/#{fixture.fetch(:conversation).id}/turns/#{fixture.fetch(:turn).public_id}/runtime_events",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/turns/#{fixture.fetch(:turn).id}/runtime_events",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/turns/#{other_turn.public_id}/runtime_events",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end
end
