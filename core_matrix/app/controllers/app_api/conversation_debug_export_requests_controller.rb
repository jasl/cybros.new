module AppAPI
  class ConversationDebugExportRequestsController < BaseController
    def create
      conversation = find_conversation!(params.fetch(:conversation_id))
      request = ConversationDebugExports::CreateRequest.call(
        conversation: conversation,
        user: conversation.workspace.user
      )

      render json: {
        method_id: "conversation_debug_export_request_create",
        conversation_id: conversation.public_id,
        debug_export_request: serialize_debug_export_request(request),
      }, status: :created
    end

    def show
      request = find_debug_export_request!(params.fetch(:id))

      render json: {
        method_id: "conversation_debug_export_request_show",
        conversation_id: request.conversation.public_id,
        debug_export_request: serialize_debug_export_request(request),
      }
    end

    def download
      request = find_debug_export_request!(params.fetch(:id))
      return head :gone unless bundle_available?(request)
      bundle_file = request.bundle_file
      bundle_blob = bundle_file.blob
      return head :gone if bundle_blob.blank?

      send_data(
        bundle_file.download,
        filename: bundle_file.filename.to_s,
        type: bundle_blob.content_type,
        disposition: :attachment
      )
    end

    private

    def find_debug_export_request!(request_id)
      ConversationDebugExportRequest.find_by!(
        public_id: request_id,
        installation_id: current_deployment.installation_id
      )
    end

    def serialize_debug_export_request(request)
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
      request.bundle_file.attached? &&
        request.bundle_file.blob.present? &&
        request.expires_at.present? &&
        request.expires_at.future? &&
        !request.expired?
    end
  end
end
