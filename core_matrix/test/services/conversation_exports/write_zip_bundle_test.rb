require "test_helper"
require "zip"

class ConversationExportsWriteZipBundleTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "writes the expected bundle files and attachment payloads into a zip archive" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Zip input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "zip attachment"
    )
    attach_selected_output!(turn, content: "Zip output")

    result = ConversationExports::WriteZipBundle.call(conversation: conversation)

    entries = []
    Zip::File.open_buffer(StringIO.new(result.fetch("io").read)) do |zip_file|
      entries = zip_file.entries.map(&:name)
    end

    assert_includes entries, "manifest.json"
    assert_includes entries, "conversation.json"
    assert_includes entries, "transcript.md"
    assert_includes entries, "conversation.html"
    assert entries.any? { |entry| entry.start_with?("files/") }
    assert_equal "conversation-export-#{conversation.public_id}.zip", result.fetch("filename")
    assert_equal "application/zip", result.fetch("content_type")
  end
end
