module ExecutionAPI
  class AttachmentsController < BaseController
    include Rails.application.routes.url_helpers

    def create
      turn = find_turn!(request_payload.fetch("turn_id"))
      authorize_turn_execution_runtime!(turn)

      attachment = find_message_attachment!(request_payload.fetch("attachment_id"))
      manifest_entry = turn.execution_snapshot&.attachment_manifest&.find do |entry|
        entry.fetch("attachment_id") == attachment.public_id
      end
      raise ActiveRecord::RecordNotFound, "Couldn't find MessageAttachment" if manifest_entry.blank?

      render json: {
        method_id: "request_attachment",
        execution_runtime_id: current_execution_runtime.public_id,
        turn_id: turn.public_id,
        conversation_id: turn.conversation.public_id,
        attachment: manifest_entry.merge(
          "blob_signed_id" => attachment.file.blob.signed_id(expires_in: 5.minutes),
          "download_url" => rails_blob_url(attachment.file, host: request.base_url),
        ),
      }
    end
  end
end
