require "test_helper"

class AgentApiConversationTranscriptsTest < ActionDispatch::IntegrationTest
  test "lists the canonical visible transcript through the machine facing api" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)
    first_turn = context[:turn]
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

    get "/agent_api/conversation_transcripts",
      params: {
        conversation_id: context[:conversation].public_id,
        limit: 2,
      },
      headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :success

    response_body = JSON.parse(response.body)
    assert_equal "conversation_transcript_list", response_body["method_id"]
    assert_equal context[:conversation].public_id, response_body["conversation_id"]
    assert_equal %w[Canonical\ variable\ input Second\ question], response_body["items"].map { |item| item.fetch("content") }
    assert_equal first_turn.selected_input_message.public_id, response_body["items"].first.fetch("id")
    assert_equal second_turn.selected_input_message.public_id, response_body["next_cursor"]
    assert_equal context[:conversation].public_id, response_body["items"].first.fetch("conversation_id")
    assert_equal first_turn.public_id, response_body["items"].first.fetch("turn_id")
    refute_includes response.body, %("#{context[:conversation].id}")
  end

  test "rejects raw bigint identifiers for conversation and cursor lookups" do
    context = build_canonical_variable_context!
    registration = register_machine_api_for_context!(context)

    get "/agent_api/conversation_transcripts",
      params: {
        conversation_id: context[:conversation].id,
      },
      headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :not_found

    get "/agent_api/conversation_transcripts",
      params: {
        conversation_id: context[:conversation].public_id,
        cursor: context[:turn].selected_input_message.id,
      },
      headers: agent_api_headers(registration[:agent_connection_credential])

    assert_response :not_found
  end
end
