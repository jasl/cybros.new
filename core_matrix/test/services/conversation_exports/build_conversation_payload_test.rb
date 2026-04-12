require "test_helper"

class ConversationExportsBuildConversationPayloadTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "builds a public-id-only payload with message-bound attachments" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export me",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "input attachment"
    )
    output_message = attach_selected_output!(turn, content: "Here is the exported answer")
    create_message_attachment!(
      message: output_message,
      filename: "output.txt",
      body: "output attachment"
    )
    conversation.update!(
      summary: "Export summary",
      summary_source: "agent"
    )

    payload = ConversationExports::BuildConversationPayload.call(conversation: conversation)

    assert_equal "conversation_export", payload.fetch("bundle_kind")
    assert_equal "2026-04-02", payload.fetch("bundle_version")
    assert_equal conversation.public_id, payload.dig("conversation", "public_id")
    assert_equal "Export me", payload.dig("conversation", "title")
    assert_equal "Export summary", payload.dig("conversation", "summary")
    assert_equal "bootstrap", payload.dig("conversation", "title_source")
    assert_equal "agent", payload.dig("conversation", "summary_source")
    assert_equal 2, payload.fetch("messages").length

    input_message = payload.fetch("messages").find { |message| message.fetch("message_public_id") == turn.selected_input_message.public_id }
    output_payload = payload.fetch("messages").find { |message| message.fetch("message_public_id") == output_message.public_id }

    assert_equal "user", input_message.fetch("role")
    assert_equal "agent", output_payload.fetch("role")
    assert_equal "user_upload", input_message.fetch("attachments").first.fetch("kind")
    assert_equal "generated_output", output_payload.fetch("attachments").first.fetch("kind")
    assert_match(/\Afiles\//, input_message.fetch("attachments").first.fetch("relative_path"))
    assert_match(/\Afiles\//, output_payload.fetch("attachments").first.fetch("relative_path"))

    json = JSON.generate(payload)
    refute_includes json, %("#{conversation.id}")
    refute_includes json, %("#{turn.id}")
  end

  test "preloads transcript and attachments without query explosion" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_definition_version: context[:agent_definition_version]
    )
    first_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export query budget input 1",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    first_source_attachment = create_message_attachment!(
      message: first_turn.selected_input_message,
      filename: "input-1.txt",
      body: "first attachment"
    )
    first_output_message = attach_selected_output!(first_turn, content: "First exported answer")
    create_message_attachment!(
      message: first_output_message,
      origin_attachment: first_source_attachment,
      filename: "output-1.txt",
      body: "first derived attachment"
    )

    second_turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Export query budget input 2",
      agent_definition_version: context[:agent_definition_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    second_source_attachment = create_message_attachment!(
      message: second_turn.selected_input_message,
      filename: "input-2.txt",
      body: "second attachment"
    )
    second_output_message = attach_selected_output!(second_turn, content: "Second exported answer")
    create_message_attachment!(
      message: second_output_message,
      origin_attachment: second_source_attachment,
      filename: "output-2.txt",
      body: "second derived attachment"
    )

    queries = capture_sql_queries do
      ConversationExports::BuildConversationPayload.call(conversation: conversation)
    end

    assert_operator queries.length, :<=, 30, "Expected conversation export payload to stay under 30 SQL queries, got #{queries.length}:\n#{queries.join("\n")}"
  end
end
