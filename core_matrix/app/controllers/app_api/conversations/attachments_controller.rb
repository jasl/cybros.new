module AppAPI
  module Conversations
    class AttachmentsController < AppAPI::Conversations::BaseController
      rescue_from Attachments::CreateForMessage::LimitExceeded do |error|
        render_method_response(
          method_id: "conversation_attachment_rejected",
          status: :unprocessable_entity,
          conversation_id: @conversation.public_id,
          rejection_reason: error.reason,
          error: error.reason
        )
      end
      rescue_from Attachments::CreateForMessage::InvalidParameters do |error|
        render_method_response(
          method_id: "conversation_attachment_rejected",
          status: :unprocessable_entity,
          conversation_id: @conversation.public_id,
          rejection_reason: error.reason,
          error: error.reason
        )
      end

      def create
        message = find_message!(params.fetch(:message_id))
        attachments = Attachments::CreateForMessage.call(
          message: message,
          files: Array(params[:files]),
          source_kind: "app_upload",
          publication_role: params[:publication_role]
        )

        render_method_response(
          method_id: "conversation_attachment_create",
          status: :created,
          conversation_id: @conversation.public_id,
          message_id: message.public_id,
          attachments: attachments.map { |attachment| serialize_message_attachment(attachment, include_download_url: true) }
        )
      end

      def show
        attachment = find_attachment!(params.fetch(:attachment_id))

        render_method_response(
          method_id: "conversation_attachment_show",
          conversation_id: @conversation.public_id,
          attachment: serialize_message_attachment(attachment, include_download_url: true)
        )
      end

      private

      def find_message!(message_public_id)
        @conversation.messages.find_by!(public_id: message_public_id)
      end

      def find_attachment!(attachment_public_id)
        MessageAttachment.find_by!(
          installation_id: current_installation_id,
          conversation_id: @conversation.id,
          public_id: attachment_public_id
        )
      end
    end
  end
end
