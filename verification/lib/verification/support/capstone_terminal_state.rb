module Verification
  module CapstoneTerminalState
    module_function

    def inspect!(conversation_id:, turn_id:, workflow_run_id:, selected_output_message_id:, selected_output_content:,
                 published_attachment_id:, published_attachment_upload_sha256:, published_attachment_download_sha256:,
                 published_attachment_export_sha256:, exported_attachment:)
      conversation = Conversation.find_by_public_id!(conversation_id)
      turn = Turn.find_by_public_id!(turn_id)
      workflow_run = WorkflowRun.find_by_public_id!(workflow_run_id)
      selected_output_message = AgentMessage.find_by_public_id!(selected_output_message_id)
      attachment = MessageAttachment.find_by_public_id!(published_attachment_id)
      blob = attachment.file.blob
      exported_attachment ||= {}

      checks = {
        "conversation_lifecycle_state" => equality_check(expected: "active", observed: conversation.lifecycle_state),
        "turn_lifecycle_state" => equality_check(expected: "completed", observed: turn.lifecycle_state),
        "workflow_run_lifecycle_state" => equality_check(expected: "completed", observed: workflow_run.lifecycle_state),
        "workflow_run_wait_state" => equality_check(expected: "ready", observed: workflow_run.wait_state),
        "turn_selected_output_message_id" => equality_check(expected: selected_output_message_id, observed: turn.selected_output_message&.public_id),
        "selected_output_message_content" => equality_check(expected: selected_output_content, observed: selected_output_message.content),
        "workflow_run_turn_id" => equality_check(expected: turn_id, observed: workflow_run.turn.public_id),
        "attachment_message_id" => equality_check(expected: selected_output_message_id, observed: attachment.message.public_id),
        "attachment_conversation_id" => equality_check(expected: conversation_id, observed: attachment.conversation.public_id),
        "attachment_publication_role" => equality_check(expected: "primary_deliverable", observed: blob.metadata["publication_role"]),
        "attachment_source_kind" => equality_check(expected: "runtime_generated", observed: blob.metadata["source_kind"]),
        "attachment_filename" => equality_check(expected: attachment.file.filename.to_s, observed: exported_attachment["filename"]),
        "attachment_mime_type" => equality_check(expected: blob.content_type, observed: exported_attachment["mime_type"]),
        "attachment_byte_size" => equality_check(expected: blob.byte_size, observed: exported_attachment["byte_size"]),
        "export_attachment_public_id" => equality_check(expected: published_attachment_id, observed: exported_attachment["attachment_public_id"]),
        "export_attachment_publication_role" => equality_check(expected: "primary_deliverable", observed: exported_attachment["publication_role"]),
        "export_attachment_source_kind" => equality_check(expected: "runtime_generated", observed: exported_attachment["source_kind"]),
        "download_sha_matches_uploaded_sha" => equality_check(expected: published_attachment_upload_sha256, observed: published_attachment_download_sha256),
        "export_sha_matches_uploaded_sha" => equality_check(expected: published_attachment_upload_sha256, observed: published_attachment_export_sha256),
        "export_sha_matches_downloaded_sha" => equality_check(expected: published_attachment_download_sha256, observed: published_attachment_export_sha256),
        "export_attachment_sha_matches_uploaded_sha" => equality_check(expected: published_attachment_upload_sha256, observed: exported_attachment["sha256"]),
      }

      {
        "passed" => checks.values.all? { |check| check.fetch("passed") },
        "checks" => checks,
        "conversation" => {
          "conversation_id" => conversation.public_id,
          "lifecycle_state" => conversation.lifecycle_state,
        },
        "turn" => {
          "turn_id" => turn.public_id,
          "lifecycle_state" => turn.lifecycle_state,
          "selected_output_message_id" => turn.selected_output_message&.public_id,
        },
        "workflow_run" => {
          "workflow_run_id" => workflow_run.public_id,
          "lifecycle_state" => workflow_run.lifecycle_state,
          "wait_state" => workflow_run.wait_state,
        },
        "selected_output_message" => {
          "message_id" => selected_output_message.public_id,
          "content" => selected_output_message.content,
        },
        "attachment" => {
          "attachment_id" => attachment.public_id,
          "message_id" => attachment.message.public_id,
          "conversation_id" => attachment.conversation.public_id,
          "filename" => attachment.file.filename.to_s,
          "content_type" => blob.content_type,
          "byte_size" => blob.byte_size,
          "publication_role" => blob.metadata["publication_role"],
          "source_kind" => blob.metadata["source_kind"],
        },
        "exported_attachment" => exported_attachment,
      }
    end

    def equality_check(expected:, observed:)
      {
        "expected" => expected,
        "observed" => observed,
        "passed" => expected == observed,
      }
    end
    private_class_method :equality_check
  end
end
