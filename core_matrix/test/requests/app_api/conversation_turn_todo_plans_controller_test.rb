require "test_helper"

class AppApiConversationTurnTodoPlansControllerTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "lists the current turn todo plan view for a supervised conversation" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_todo_plans_path(
      conversation_id: fixture.fetch(:conversation).public_id
    ), headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "conversation_turn_todo_plan_list", body.fetch("method_id")
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    assert_equal "render-snapshot", body.fetch("primary_turn_todo_plan").fetch("current_item_key")
    assert_equal ["check-hard-gate"],
      body.fetch("active_subagent_turn_todo_plans").map { |entry| entry.fetch("current_item_key") }
    refute_includes response.body, %("#{fixture.fetch(:conversation).id}")
  end

  test "rejects raw bigint conversation identifiers" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_todo_plans_path(
      conversation_id: fixture.fetch(:conversation).id
    ), headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :not_found
  end

  test "omits the primary turn todo plan when provider-backed work has no persisted plan" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    get app_api_conversation_turn_todo_plans_path(
      conversation_id: fixture.fetch(:conversation).public_id
    ), headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    refute body.key?("primary_turn_todo_plan")
  end
end
