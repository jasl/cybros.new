require "test_helper"

class AppApiConversationTurnFeedsControllerTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "lists the canonical turn feed for a supervised conversation" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_feeds_path(
      conversation_id: fixture.fetch(:conversation).public_id
    ), headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "conversation_turn_feed_list", body.fetch("method_id")
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    assert_includes body.fetch("items").map { |entry| entry.fetch("event_kind") }, "turn_todo_item_started"
    refute_includes body.fetch("items").map { |entry| entry.fetch("event_kind") }, "progress_recorded"
  end

  test "rejects raw bigint conversation identifiers" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_feeds_path(
      conversation_id: fixture.fetch(:conversation).id
    ), headers: app_api_headers(registration[:machine_credential])

    assert_response :not_found
  end

  test "lists coarse canonical turn feed entries for provider-backed work without an agent task run" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_feeds_path(
      conversation_id: fixture.fetch(:conversation).public_id
    ), headers: app_api_headers(registration[:machine_credential])

    assert_response :success

    body = JSON.parse(response.body)
    refute body.fetch("items").any? { |entry| entry.fetch("event_kind").start_with?("turn_todo_") }
    assert_includes body.fetch("items").map { |entry| entry.fetch("event_kind") }, "turn_started"
    refute_match(/provider round|command_run_wait|exec_command|React app|game files/i, body.to_json)
  end
end
