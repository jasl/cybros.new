require "test_helper"

class AppApiConversationTurnFeedsControllerTest < ActionDispatch::IntegrationTest
  include ConversationSupervisionFixtureBuilder

  test "lists the canonical turn feed for a supervised conversation" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/feed",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    body = JSON.parse(response.body)
    assert_equal "conversation_turn_feed_list", body.fetch("method_id")
    assert_equal fixture.fetch(:conversation).public_id, body.fetch("conversation_id")
    assert_includes body.fetch("items").map { |entry| entry.fetch("event_kind") }, "turn_todo_item_started"
    refute_includes body.fetch("items").map { |entry| entry.fetch("event_kind") }, "progress_recorded"
  end

  test "does not recreate supervision state inside the feed request" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)
    fixture.fetch(:conversation).conversation_supervision_state.destroy!

    assert_no_difference("ConversationSupervisionState.count") do
      get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/feed",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
    assert_includes response.parsed_body.fetch("items").map { |entry| entry.fetch("event_kind") }, "turn_todo_item_started"
  end

  test "lists the canonical turn feed within twenty-seven SQL queries" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    assert_sql_query_count_at_most(27) do
      get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/feed",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  end

  test "rejects raw bigint conversation identifiers" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).id}/feed",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end

  test "lists coarse canonical turn feed entries for provider-backed work without an agent task run" do
    fixture = prepare_provider_backed_conversation_supervision_context!
    registration = register_machine_api_for_context!(fixture)

    get "/app_api/conversations/#{fixture.fetch(:conversation).public_id}/feed",
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    body = JSON.parse(response.body)
    refute body.fetch("items").any? { |entry| entry.fetch("event_kind").start_with?("turn_todo_") }
    assert_includes body.fetch("items").map { |entry| entry.fetch("event_kind") }, "turn_started"
    refute_match(/provider round|command_run_wait|exec_command|React app|game files/i, body.to_json)
  end

  test "does not regress queued turn-bootstrap supervision while listing an empty feed" do
    context = create_workspace_context!
    session = create_session!(user: context[:user])
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace], agent: context[:agent])
    turn = Turns::AcceptPendingUserTurn.call(
      conversation: conversation,
      content: "Build a complete browser-playable React 2048 game and add automated tests.",
      selector_source: "app_api",
      selector: "candidate:codex_subscription/gpt-5.3-codex"
    )

    get "/app_api/conversations/#{conversation.public_id}/feed",
      headers: app_api_headers(session.plaintext_token)

    assert_response :success
    assert_equal [], response.parsed_body.fetch("items")

    state = conversation.reload.conversation_supervision_state
    assert_equal "queued", state.overall_state
    assert_equal "turn", state.current_owner_kind
    assert_equal turn.public_id, state.current_owner_public_id
  end

  test "returns an empty feed when anchors are missing without repairing supervision in request" do
    fixture = prepare_conversation_supervision_context_with_turn_todo_plan!
    registration = register_machine_api_for_context!(fixture)
    conversation = fixture.fetch(:conversation)
    conversation.update!(latest_active_turn_id: nil, latest_turn_id: nil)
    conversation.conversation_supervision_state.destroy!

    assert_no_difference("ConversationSupervisionState.count") do
      get "/app_api/conversations/#{conversation.public_id}/feed",
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
    assert_equal [], response.parsed_body.fetch("items")
  end
end
