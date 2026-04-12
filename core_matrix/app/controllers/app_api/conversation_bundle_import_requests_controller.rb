module AppAPI
  class ConversationBundleImportRequestsController < BaseController
    def create
      workspace = find_workspace!(params.fetch(:workspace_id))
      request = ConversationBundleImports::CreateRequest.call(
        workspace: workspace,
        user: workspace.user,
        uploaded_file: params[:upload_file],
        target_agent_definition_version_id: current_agent_definition_version.public_id
      )

      render json: {
        method_id: "conversation_bundle_import_request_create",
        workspace_id: workspace.public_id,
        import_request: serialize_import_request(request),
      }, status: :created
    end

    def show
      request = find_import_request!(params.fetch(:id))

      render json: {
        method_id: "conversation_bundle_import_request_show",
        workspace_id: request.workspace.public_id,
        import_request: serialize_import_request(request),
      }
    end

    private

    def find_import_request!(request_id)
      ConversationBundleImportRequest.find_by!(
        public_id: request_id,
        installation_id: current_agent_definition_version.installation_id
      )
    end

    def serialize_import_request(request)
      imported_conversation_id = request.imported_conversation&.public_id ||
        request.result_payload.fetch("imported_conversation_id", nil)

      {
        "request_id" => request.public_id,
        "workspace_id" => request.workspace.public_id,
        "user_id" => request.user.public_id,
        "imported_conversation_id" => imported_conversation_id,
        "lifecycle_state" => request.lifecycle_state,
        "created_at" => request.created_at&.iso8601(6),
        "queued_at" => request.queued_at&.iso8601(6),
        "started_at" => request.started_at&.iso8601(6),
        "finished_at" => request.finished_at&.iso8601(6),
        "upload_received" => request.upload_file.attached?,
        "upload_filename" => request.upload_file.attached? ? request.upload_file.filename.to_s : nil,
        "upload_content_type" => request.upload_file.attached? ? request.upload_file.blob.content_type : nil,
        "result_payload" => request.result_payload,
        "failure_payload" => request.failure_payload,
      }.compact
    end
  end
end
