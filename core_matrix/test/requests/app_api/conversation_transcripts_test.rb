require "test_helper"

class AppApiConversationTranscriptsTest < ActionDispatch::IntegrationTest
  test "lists the canonical visible transcript through the app api" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    first_turn = context[:turn]
    input_attachment = create_message_attachment!(
      message: first_turn.selected_input_message,
      filename: "input.txt",
      body: "input attachment"
    )
    input_attachment.file.blob.update!(metadata: input_attachment.file.blob.metadata.merge("publication_role" => "evidence"))
    first_output = attach_selected_output!(first_turn, content: "First answer")
    second_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Second question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(second_turn, content: "Second answer")
    ConversationMessageVisibility.create!(
      installation: context[:installation],
      conversation: context[:conversation],
      message: first_output,
      hidden: true,
      excluded_from_context: false
    )

    get "/app_api/conversations/#{context[:conversation].public_id}/transcript",
      params: {
        limit: 2,
      },
      headers: app_api_headers(registration[:session_token])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_transcript_list", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal %w[Canonical\ variable\ input Second\ question], response_body["items"].map { |item| item.fetch("content") }
    assert_equal first_turn.selected_input_message.public_id, response_body["items"].first.fetch("id")
    assert_equal second_turn.selected_input_message.public_id, response_body["next_cursor"]
    assert_equal context[:conversation].public_id, response_body["items"].first.fetch("conversation_id")
    assert_equal first_turn.public_id, response_body["items"].first.fetch("turn_id")
    assert_equal input_attachment.public_id, response_body["items"].first.dig("attachments", 0, "attachment_id")
    assert_equal "evidence", response_body["items"].first.dig("attachments", 0, "publication_role")
    refute_includes response.body, %("#{context[:conversation].id}")
  end

  test "lists the canonical visible transcript within nine SQL queries" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    first_turn = context[:turn]
    attach_selected_output!(first_turn, content: "First answer")
    second_turn = Turns::StartUserTurn.call(
      conversation: context[:conversation],
      content: "Second question",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    attach_selected_output!(second_turn, content: "Second answer")

    assert_sql_query_count_at_most(9) do
      get "/app_api/conversations/#{context[:conversation].public_id}/transcript",
        params: { limit: 2 },
        headers: app_api_headers(registration[:session_token])
    end

    assert_response :success
  end

  test "rejects raw bigint identifiers for conversation and cursor lookups" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    get "/app_api/conversations/#{context[:conversation].id}/transcript",
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found

    get "/app_api/conversations/#{context[:conversation].public_id}/transcript",
      params: {
        cursor: context[:turn].selected_input_message.id,
      },
      headers: app_api_headers(registration[:session_token])

    assert_response :not_found
  end
end
