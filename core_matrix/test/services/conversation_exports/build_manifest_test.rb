require "test_helper"

class ConversationExportsBuildManifestTest < ActiveSupport::TestCase
  setup do
    truncate_all_tables!
  end

  test "builds a versioned manifest for the exported conversation assets" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(
      workspace: context[:workspace],
    )
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Manifest input",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    create_message_attachment!(
      message: turn.selected_input_message,
      filename: "input.txt",
      body: "input attachment"
    )
    output_message = attach_selected_output!(turn, content: "Manifest output")
    create_message_attachment!(
      message: output_message,
      filename: "output.txt",
      body: "output attachment"
    )
    conversation.update!(
      summary: "Manifest summary",
      summary_source: "agent"
    )

    conversation_payload = ConversationExports::BuildConversationPayload.call(conversation: conversation)
    manifest = ConversationExports::BuildManifest.call(
      conversation: conversation,
      conversation_payload: conversation_payload
    )

    assert_equal "conversation_export", manifest.fetch("bundle_kind")
    assert_equal "2026-04-02", manifest.fetch("bundle_version")
    assert_equal conversation.public_id, manifest.fetch("conversation_public_id")
    assert_equal "Manifest input", manifest.fetch("title")
    assert_equal "Manifest summary", manifest.fetch("summary")
    assert_equal "bootstrap", manifest.fetch("title_source")
    assert_equal "agent", manifest.fetch("summary_source")
    assert_equal 2, manifest.fetch("message_count")
    assert_equal 2, manifest.fetch("attachment_count")
    assert_equal 2, manifest.fetch("files").length
    assert_equal %w[generated_output user_upload], manifest.fetch("files").map { |item| item.fetch("kind") }.sort
    assert_kind_of Hash, manifest.fetch("checksums")
    assert_kind_of Hash, manifest.fetch("generator")

    json = JSON.generate(manifest)
    refute_includes json, %("#{conversation.id}")
    refute_includes json, %("#{turn.id}")
  end
end
