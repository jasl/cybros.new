require "test_helper"

class AppApiConversationTurnTodoPlansControllerTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "lists the current turn todo plan view for a supervised conversation" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/todo_plan",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "conversation_turn_todo_plan_list", body.fetch("method_id")
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    assert_equal "render-snapshot", body.fetch("primary_turn_todo_plan").fetch("current_item_key")
    assert_equal ["check-hard-gate"],
      body.fetch("active_subagent_turn_todo_plans").map { |entry| entry.fetch("current_item_key") }
    refute_includes response.body, %("#{fixture.fetch(:conversation).id}")
  end

  test "lists the current turn todo plan view within thirty-two SQL queries" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    assert_sql_query_count_at_most(32) do
      get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/todo_plan",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  end

  test "rejects raw bigint conversation identifiers" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).id}/todo_plan",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "omits the primary turn todo plan when provider-backed work has no persisted plan" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/todo_plan",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    refute body.key?("primary_turn_todo_plan")
  end

  test "preserves queued turn-bootstrap supervision while returning no todo plan" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Build a complete browser-playable React 2048 game and add automated tests.",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    get "/app_api/conversations/#{conversation.public_id}/todo_plan",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal conversation.public_id, body.fetch("conversation_id")
    refute body.key?("primary_turn_todo_plan")

    state = conversation.reload.conversation_supervision_state
    assert_equal "queued", state.overall_state
    assert_equal "turn", state.current_owner_kind
    assert_equal turn.public_id, state.current_owner_public_id
  end
end
