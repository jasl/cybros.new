module ExecutionRuntimeAPI
  class AttachmentsController < BaseController
    include Rails.application.routes.url_helpers

    rescue_from Attachments::CreateForMessage::LimitExceeded, with: :render_publish_rejected
    rescue_from Attachments::CreateForMessage::InvalidParameters, with: :render_publish_rejected
    rescue_from Attachments::PublishRuntimeOutput::InvalidParameters, with: :render_publish_rejected

    def create
      turn = find_turn!(request_payload.fetch("turn_id"))
      authorize_turn_execution_runtime!(turn)

      attachment = find_message_attachment!(request_payload.fetch("attachment_id"))
      manifest_entry = turn.execution_snapshot&.attachment_manifest&.find do |entry|
        entry.fetch("attachment_id") == attachment.public_id
      end
      raise ActiveRecord::RecordNotFound, "Couldn't find MessageAttachment" if manifest_entry.blank?

      render json: {
        method_id: "refresh_attachment",
        execution_runtime_id: current_execution_runtime.public_id,
        turn_id: turn.public_id,
        conversation_id: turn.conversation.public_id,
        attachment: manifest_entry.merge(
          "blob_signed_id" => attachment.file.blob.signed_id(expires_in: 5.minutes),
          "download_url" => rails_blob_url(attachment.file, host: request.base_url),
        ),
      }
    end

    def publish
      turn = find_turn!(request_payload.fetch("turn_id"))
      authorize_turn_execution_runtime!(turn)

      attachments = Attachments::PublishRuntimeOutput.call(
        turn: turn,
        files: Array(params[:file] || params[:files]),
        publication_role: request_payload["publication_role"]
      )

      render json: {
        method_id: "publish_attachment",
        execution_runtime_id: current_execution_runtime.public_id,
        turn_id: turn.public_id,
        conversation_id: turn.conversation.public_id,
        attachments: attachments.map { |attachment| serialize_attachment(attachment) },
      }, status: :created
    end

    private

    def find_message_attachment!(attachment_id)
      MessageAttachment.find_by_public_id!(attachment_id)
    end

    def serialize_attachment(attachment)
      {
        "attachment_id" => attachment.public_id,
        "filename" => attachment.file.filename.to_s,
        "content_type" => attachment.file.blob.content_type,
        "byte_size" => attachment.file.blob.byte_size,
        "publication_role" => Attachments::CreateForMessage.publication_role_for(attachment),
        "source_kind" => Attachments::CreateForMessage.source_kind_for(attachment),
        "blob_signed_id" => attachment.file.blob.signed_id(expires_in: 5.minutes),
        "download_url" => rails_blob_url(attachment.file, host: request.base_url),
      }.compact
    end

    def render_publish_rejected(error)
      render json: {
        method_id: "publish_attachment_rejected",
        execution_runtime_id: current_execution_runtime.public_id,
        error: error.reason,
      }, status: :unprocessable_entity
    end
  end
end
