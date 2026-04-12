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
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_metadata_show", response_body["method_id"]
    metadata = response_body.fetch("metadata")
    assert_equal conversation.public_id, metadata["conversation_id"]
    assert_equal "Conversation title", metadata["title"]
    assert_equal "Conversation summary", metadata["summary"]
    assert_equal "agent", metadata["title_source"]
    assert_equal "generated", metadata["summary_source"]
    assert_equal true, metadata["title_locked"]
    assert_equal false, metadata["summary_locked"]
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
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_metadata_update", response_body["method_id"]
    metadata = response_body.fetch("metadata")
    assert_equal conversation.public_id, metadata["conversation_id"]
    assert_equal "Pinned by user", metadata["title"]
    assert_equal "user", metadata["title_source"]
    assert_equal true, metadata["title_locked"]
    assert_equal "Existing summary", metadata["summary"]
    assert_equal "generated", metadata["summary_source"]
    assert_equal false, metadata["summary_locked"]
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
        headers: app_api_headers(registration[:session_token])
    ensure
      Conversations::Metadata::GenerateField.singleton_class.send(:define_method, :call, original_call)
    end

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_metadata_regenerate", response_body["method_id"]
    metadata = response_body.fetch("metadata")
    assert_equal conversation.public_id, metadata["conversation_id"]
    assert_equal "Generated title", metadata["title"]
    assert_equal false, metadata["title_locked"]
    assert_equal true, metadata["summary_locked"]
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
      headers: app_api_headers(registration[:session_token])

    assert_response :unprocessable_entity
    assert_includes response.body, "generation is unavailable"
  end

  test "rejects bigint ids for metadata app api endpoints" do
    context = fresh_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    conversation = context[:conversation]

    get "/app_api/conversations/#{conversation.id}/metadata",
      headers: app_api_headers(registration[:session_token])
    assert_response :not_found

    patch "/app_api/conversations/#{conversation.id}/metadata",
      params: { title: "new title" }.to_json,
      headers: app_api_headers(registration[:session_token])
    assert_response :not_found

    post "/app_api/conversations/#{conversation.id}/metadata/regenerate",
      params: { field: "title" }.to_json,
      headers: app_api_headers(registration[:session_token])
    assert_response :not_found
  end

  test "routes put metadata updates through the standard resource update action" do
    context = fresh_canonical_variable_context!
    conversation = context[:conversation]

    recognized = Rails.application.routes.recognize_path(
      "/app_api/conversations/#{conversation.public_id}/metadata",
      method: :put
    )

    assert_equal "app_api/conversations/metadata", recognized.fetch(:controller)
    assert_equal "update", recognized.fetch(:action)
    assert_equal conversation.public_id, recognized.fetch(:conversation_id)
  end

  private

  def fresh_canonical_variable_context!
    delete_all_table_rows!
    build_canonical_variable_context!
  end
end
