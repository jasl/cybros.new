require_relative "../core_matrix_hosted_test_helper"
require "verification/support/capstone_terminal_state"

class Verification::CapstoneTerminalStateTest < ActiveSupport::TestCase
  test "inspect! verifies the persisted terminal state for the selected output attachment" do
    context = build_canonical_variable_context!
    turn = context.fetch(:turn)
    workflow_run = context.fetch(:workflow_run)
    output_message = attach_selected_output!(turn, content: "Finished the build")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "game-2048-dist.zip",
      content_type: "application/zip",
      body: "zip payload"
    )
    attachment.file.blob.update!(
      metadata: attachment.file.blob.metadata.merge(
        "publication_role" => "primary_deliverable",
        "source_kind" => "runtime_generated"
      )
    )
    workflow_run.update!(lifecycle_state: "completed", wait_state: "ready")
    turn.update!(lifecycle_state: "completed", selected_output_message: output_message)

    result = Verification::CapstoneTerminalState.inspect!(
      conversation_id: context.fetch(:conversation).public_id,
      turn_id: turn.public_id,
      workflow_run_id: workflow_run.public_id,
      selected_output_message_id: output_message.public_id,
      selected_output_content: output_message.content,
      published_attachment_id: attachment.public_id,
      published_attachment_upload_sha256: "upload-sha",
      published_attachment_download_sha256: "upload-sha",
      published_attachment_export_sha256: "upload-sha",
      exported_attachment: {
        "attachment_public_id" => attachment.public_id,
        "filename" => "game-2048-dist.zip",
        "mime_type" => "application/zip",
        "byte_size" => attachment.file.blob.byte_size,
        "publication_role" => "primary_deliverable",
        "source_kind" => "runtime_generated",
        "sha256" => "upload-sha",
      }
    )

    assert result.fetch("passed")
    assert_equal "completed", result.dig("turn", "lifecycle_state")
    assert_equal "ready", result.dig("workflow_run", "wait_state")
    assert_equal "primary_deliverable", result.dig("attachment", "publication_role")
    assert_equal "runtime_generated", result.dig("attachment", "source_kind")
  end

  test "inspect! fails when the exported artifact no longer matches the stored attachment contract" do
    context = build_canonical_variable_context!
    turn = context.fetch(:turn)
    workflow_run = context.fetch(:workflow_run)
    output_message = attach_selected_output!(turn, content: "Finished the build")
    attachment = create_message_attachment!(
      message: output_message,
      filename: "game-2048-dist.zip",
      content_type: "application/zip",
      body: "zip payload"
    )
    attachment.file.blob.update!(
      metadata: attachment.file.blob.metadata.merge(
        "publication_role" => "primary_deliverable",
        "source_kind" => "runtime_generated"
      )
    )
    workflow_run.update!(lifecycle_state: "completed", wait_state: "ready")
    turn.update!(lifecycle_state: "completed", selected_output_message: output_message)

    result = Verification::CapstoneTerminalState.inspect!(
      conversation_id: context.fetch(:conversation).public_id,
      turn_id: turn.public_id,
      workflow_run_id: workflow_run.public_id,
      selected_output_message_id: output_message.public_id,
      selected_output_content: output_message.content,
      published_attachment_id: attachment.public_id,
      published_attachment_upload_sha256: "upload-sha",
      published_attachment_download_sha256: "upload-sha",
      published_attachment_export_sha256: "different-export-sha",
      exported_attachment: {
        "attachment_public_id" => attachment.public_id,
        "filename" => "game-2048-dist.zip",
        "mime_type" => "application/zip",
        "byte_size" => attachment.file.blob.byte_size,
        "publication_role" => "primary_deliverable",
        "source_kind" => "runtime_generated",
        "sha256" => "upload-sha",
      }
    )

    refute result.fetch("passed")
    refute result.dig("checks", "export_sha_matches_uploaded_sha", "passed")
  end
end
