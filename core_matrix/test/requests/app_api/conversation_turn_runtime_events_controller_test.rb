require "test_helper"

class AppApiConversationTurnRuntimeEventsControllerTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "lists the canonical turn runtime event stream for a conversation turn" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_runtime_events_path(
      conversation_id: fixture.fetch(:conversation).public_id,
      turn_id: fixture.fetch(:turn).public_id
    ), headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "conversation_turn_runtime_event_list", body.fetch("method_id")
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    assert_equal fixture.fetch(:turn).public_id, body.fetch("turn_id")
    assert_includes body.fetch("lanes").map { |lane| lane.fetch("actor_label") }, "main"

    summaries = body.fetch("items").map { |entry| entry.fetch("summary") }
    assert_includes summaries, "Ran the test run in /workspace/game-2048"
    assert_includes summaries, "Running the test-and-build check in /workspace/game-2048"

    current_check = body.fetch("items").find do |entry|
      entry.fetch("summary") == "Running the test-and-build check in /workspace/game-2048"
    end

    assert_equal fixture.fetch(:active_command_run).public_id, current_check.fetch("command_run_public_id")
    assert current_check.fetch("workflow_node_key").present?
    refute_includes response.body, %("#{fixture.fetch(:conversation).id}")
    refute_includes response.body, %("#{fixture.fetch(:turn).id}")
  end
end
