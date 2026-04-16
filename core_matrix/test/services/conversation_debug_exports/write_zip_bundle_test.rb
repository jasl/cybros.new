require "test_helper"

class ConversationDebugExportsWriteZipBundleTest < ActiveSupport::TestCase
  include ConversationSupervisionFixtureBuilder

  test "writes a debug zip bundle with diagnostic sections and attached files" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Debug zip input",
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
    assert_includes entries, "workflow_edges.json"
    assert_includes entries, "workflow_artifacts.json"
    assert_includes entries, "conversation_supervision_sessions.json"
    assert_includes entries, "conversation_supervision_messages.json"
    assert_includes entries, "usage_events.json"
    assert entries.any? { |entry| entry.start_with?("files/") }
    assert_equal "conversation_debug_export", bundle.dig("manifest", "bundle_kind")
    assert_includes bundle.dig("manifest", "section_files"), "workflow_edges.json"
    assert_includes bundle.dig("manifest", "section_files"), "workflow_artifacts.json"
  ensure
    bundle&.fetch("io")&.close!
  end

  test "writes supervision transcript sections when sidechat messages exist" do
    fixture = prepare_conversation_supervision_context!
    session = create_conversation_supervision_session!(fixture)
    EmbeddedAgents::ConversationSupervision::AppendMessage.call(
      actor: fixture.fetch(:user),
      conversation_supervision_session: session,
      content: "What changed most recently?"
    )

    bundle = ConversationDebugExports::WriteZipBundle.call(conversation: fixture.fetch(:conversation))
    session_payload = nil
    message_payload = nil

    Zip::File.open(bundle.fetch("io").path) do |zip_file|
      session_payload = JSON.parse(zip_file.read("conversation_supervision_sessions.json"))
      message_payload = JSON.parse(zip_file.read("conversation_supervision_messages.json"))
    end

    assert_equal session.public_id, session_payload.first.fetch("supervision_session_id")
    assert_equal %w[user supervisor_agent], message_payload.map { |message| message.fetch("role") }
  ensure
    bundle&.fetch("io")&.close!
  end
end
