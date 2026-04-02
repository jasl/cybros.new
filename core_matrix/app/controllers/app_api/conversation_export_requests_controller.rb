module AppAPI
  class ConversationExportRequestsController < BaseController
    def create
      conversation = find_conversation!(params.fetch(:conversation_id))
      request = ConversationExports::CreateRequest.call(
        conversation: conversation,
        user: conversation.workspace.user
      )

      render json: {
        method_id: "conversation_export_request_create",
        conversation_id: conversation.public_id,
        export_request: serialize_export_request(request),
      }, status: :created
    end

    def show
      request = find_export_request!(params.fetch(:id))

      render json: {
        method_id: "conversation_export_request_show",
        conversation_id: request.conversation.public_id,
        export_request: serialize_export_request(request),
      }
    end

    def download
      request = find_export_request!(params.fetch(:id))
      return head :gone unless bundle_available?(request)

      send_data(
        request.bundle_file.download,
        filename: request.bundle_file.filename.to_s,
        type: request.bundle_file.blob.content_type,
        disposition: "attachment"
      )
    end

    private

    def find_export_request!(request_id)
      ConversationExportRequest.find_by!(
        public_id: request_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_export_request(request)
      {
        "request_id" => request.public_id,
        "workspace_id" => request.workspace.public_id,
        "conversation_id" => request.conversation.public_id,
        "user_id" => request.user.public_id,
        "lifecycle_state" => request.lifecycle_state,
        "created_at" => request.created_at&.iso8601(6),
        "queued_at" => request.queued_at&.iso8601(6),
        "started_at" => request.started_at&.iso8601(6),
        "finished_at" => request.finished_at&.iso8601(6),
        "expires_at" => request.expires_at&.iso8601(6),
        "bundle_available" => bundle_available?(request),
        "result_payload" => request.result_payload,
        "failure_payload" => request.failure_payload,
      }.compact
    end

    def bundle_available?(request)
      request.bundle_file.attached? && request.expires_at.present? && request.expires_at.future? && !request.expired?
    end
  end
end
