require "test_helper"

class AppApiConversationsMetadataTest < ActionDispatch::IntegrationTest
  test "shows canonical conversation metadata by public id" do
    context = fresh_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    conversation = context[:conversation]
    conversation.update!(
      title: "Conversation title",
      summary: "Conversation summary",
      title_source: "agent",
      summary_source: "generated",
      title_lock_state: "user_locked",
      summary_lock_state: "unlocked"
    )

    get "/app_api/conversations/#{conversation.public_id}/metadata",
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal conversation.public_id, response_body["conversation_id"]
    assert_equal "Conversation title", response_body["title"]
    assert_equal "Conversation summary", response_body["summary"]
    assert_equal "agent", response_body["title_source"]
    assert_equal "generated", response_body["summary_source"]
    assert_equal true, response_body["title_locked"]
    assert_equal false, response_body["summary_locked"]
    refute_includes response.body, %("#{conversation.id}")
  end

  test "patch edits metadata through user edit service" do
    context = fresh_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    conversation = context[:conversation]
    conversation.update!(
      summary: "Existing summary",
      summary_source: "generated",
      summary_lock_state: "unlocked"
    )

    patch "/app_api/conversations/#{conversation.public_id}/metadata",
      params: { title: "Pinned by user" }.to_json,
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal conversation.public_id, response_body["conversation_id"]
    assert_equal "Pinned by user", response_body["title"]
    assert_equal "user", response_body["title_source"]
    assert_equal true, response_body["title_locked"]
    assert_equal "Existing summary", response_body["summary"]
    assert_equal "generated", response_body["summary_source"]
    assert_equal false, response_body["summary_locked"]
  end

  test "regenerate clears only the targeted metadata lock" do
    context = fresh_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    conversation = context[:conversation]
    conversation.update!(
      title: "Pinned title",
      summary: "Pinned summary",
      title_source: "user",
      summary_source: "user",
      title_lock_state: "user_locked",
      summary_lock_state: "user_locked"
    )
    original_call = Conversations::Metadata::GenerateField.method(:call)
    Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call) do |conversation: _, field: _, occurred_at: _, persist: _, **_kwargs|
      "Generated title"
    end

    begin
      post "/app_api/conversations/#{conversation.public_id}/metadata/regenerate",
        params: { field: "title" }.to_json,
        headers: app_api_headers(registration[:agent_connection_credential])
    ensure
      Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call, original_call)
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal conversation.public_id, response_body["conversation_id"]
    assert_equal "Generated title", response_body["title"]
    assert_equal false, response_body["title_locked"]
    assert_equal true, response_body["summary_locked"]
  end

  test "returns unprocessable entity when metadata regeneration is unavailable" do
    context = fresh_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    conversation = context[:conversation]
    conversation.update!(
      title: "Pinned title",
      title_source: "user",
      title_lock_state: "user_locked"
    )

    post "/app_api/conversations/#{conversation.public_id}/metadata/regenerate",
      params: { field: "title" }.to_json,
      headers: app_api_headers(registration[:agent_connection_credential])

    assert_response :unprocessable_entity
    assert_includes response.body, "generation is unavailable"
  end

  test "rejects bigint ids for metadata app api endpoints" do
    context = fresh_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    conversation = context[:conversation]

    get "/app_api/conversations/#{conversation.id}/metadata",
      headers: app_api_headers(registration[:agent_connection_credential])
    assert_response :not_found

    patch "/app_api/conversations/#{conversation.id}/metadata",
      params: { title: "new title" }.to_json,
      headers: app_api_headers(registration[:agent_connection_credential])
    assert_response :not_found

    post "/app_api/conversations/#{conversation.id}/metadata/regenerate",
      params: { field: "title" }.to_json,
      headers: app_api_headers(registration[:agent_connection_credential])
    assert_response :not_found
  end

  test "does not route put metadata updates" do
    context = fresh_canonical_variable_context!
    conversation = context[:conversation]

    assert_raises(ActionController::RoutingError) do
      Rails.application.routes.recognize_path(
        "/app_api/conversations/#{conversation.public_id}/metadata",
        method: :put
      )
    end
  end

  private

  def fresh_canonical_variable_context!
    delete_all_table_rows!
    build_canonical_variable_context!
  end
end
