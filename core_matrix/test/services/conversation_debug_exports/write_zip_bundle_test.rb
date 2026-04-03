require "test_helper"

class ConversationDebugExportsWriteZipBundleTest < ActiveSupport::TestCase
  test "writes a debug zip bundle with diagnostic sections and attached files" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
      execution_runtime: context[:execution_runtime],
      agent_program_version: context[:agent_program_version]
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug zip input",
      agent_program_version: context[:agent_program_version],
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "debug zip attachment"
    )
    attach_selected_output!(turn, content: "Debug zip output")

    bundle = ConversationDebugExports::WriteZipBundle.call(conversation: conversation)
    entries = []

    Zip::File.open(bundle.fetch("io").path) do |zip_file|
      entries = zip_file.glob("**/*").reject(&:directory?).map(&:name)
    end

    assert_includes entries, "manifest.json"
    assert_includes entries, "conversation.json"
    assert_includes entries, "diagnostics.json"
    assert_includes entries, "workflow_runs.json"
    assert_includes entries, "usage_events.json"
    assert entries.any? { |entry| entry.start_with?("files/") }
    assert_equal "conversation_debug_export", bundle.dig("manifest", "bundle_kind")
  ensure
    bundle&.fetch("io")&.close!
  end
end
