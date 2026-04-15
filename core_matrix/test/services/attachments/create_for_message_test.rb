require "test_helper"

class Attachments::CreateForMessageTest < ActiveSupport::TestCase
  test "creates attachments for a message from runtime-generated files and stamps publication metadata" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish artifact",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    output_message = attach_selected_output!(turn, content: "Artifact ready")
    bundle = Tempfile.new(["dist", ".zip"])
    bundle.write("bundle-bytes")
    bundle.rewind

    attachments = Attachments::CreateForMessage.call(
      message: output_message,
      files: [
        {
          path: bundle.path,
          filename: "dist.zip",
          content_type: "application/zip",
          publication_role: "primary_deliverable"
        }
      ],
      source_kind: "runtime_generated"
    )

    attachment = attachments.fetch(0)

    assert_equal 1, attachments.length
    assert_equal output_message, attachment.message
    assert_equal "dist.zip", attachment.file.filename.to_s
    assert_equal "primary_deliverable", attachment.file.blob.metadata["publication_role"]
    assert_equal "runtime_generated", attachment.file.blob.metadata["source_kind"]
  ensure
    bundle&.close!
  end

  test "rejects oversize files before creating any attachment rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish artifact",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )
    oversized = Tempfile.new(["oversized", ".txt"])
    oversized.write("123456789")
    oversized.rewind

    assert_no_difference("MessageAttachment.count") do
      error = assert_raises(Attachments::CreateForMessage::AttachmentTooLarge) do
        Attachments::CreateForMessage.call(
          message: turn.selected_input_message,
          files: [{ path: oversized.path, filename: "oversized.txt", content_type: "text/plain" }],
          max_bytes: 8
        )
      end

      assert_equal "attachment_too_large", error.reason
    end
  ensure
    oversized&.close!
  end

  test "rejects batches that exceed the configured attachment count before creating rows" do
    context = create_workspace_context!
    conversation = Conversations::CreateRoot.call(workspace: context[:workspace])
    turn = Turns::StartUserTurn.call(
      conversation: conversation,
      content: "Publish artifact",
      resolved_config_snapshot: {},
      resolved_model_selection_snapshot: {}
    )

    files = [
      { io: StringIO.new("first"), filename: "first.txt", content_type: "text/plain" },
      { io: StringIO.new("second"), filename: "second.txt", content_type: "text/plain" }
    ]

    assert_no_difference("MessageAttachment.count") do
      error = assert_raises(Attachments::CreateForMessage::AttachmentCountExceeded) do
        Attachments::CreateForMessage.call(
          message: turn.selected_input_message,
          files: files,
          max_count: 1
        )
      end

      assert_equal "attachment_count_exceeded", error.reason
    end
  end
end
