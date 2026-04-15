module ConversationBundleImports
  class CreateRequest
    def self.call(...)
      new(...).call
    end

    def initialize(workspace:, user:, workspace_agent:, uploaded_file:, target_agent_definition_version_id:)
      @workspace = workspace
      @user = user
      @workspace_agent = workspace_agent
      @uploaded_file = uploaded_file
      @target_agent_definition_version_id = target_agent_definition_version_id
    end

    def call
      request = ConversationBundleImportRequest.new(
        installation: @workspace.installation,
        workspace: @workspace,
        user: @user,
        lifecycle_state: "queued",
        queued_at: Time.current,
        request_payload: {
          "bundle_kind" => ConversationExports::BuildConversationPayload::BUNDLE_KIND,
          "bundle_version" => ConversationExports::BuildConversationPayload::BUNDLE_VERSION,
          "target_agent_definition_version_id" => @target_agent_definition_version_id,
          "target_workspace_agent_id" => @workspace_agent.public_id,
          "upload_filename" => upload_filename,
          "upload_content_type" => upload_content_type,
        }.compact
      )
      attach_upload!(request) if @uploaded_file.present?
      request.save!

      ConversationBundleImports::ExecuteRequestJob.perform_later(request.public_id)
      request
    end

    private

    def attach_upload!(request)
      io = upload_io
      io.rewind if io.respond_to?(:rewind)

      request.upload_file.attach(
        io: io,
        filename: upload_filename,
        content_type: upload_content_type
      )
    end

    def upload_io
      return @uploaded_file.tempfile if @uploaded_file.respond_to?(:tempfile)

      @uploaded_file
    end

    def upload_filename
      @uploaded_file&.original_filename.presence || "conversation-import.zip"
    end

    def upload_content_type
      @uploaded_file&.content_type.presence || "application/zip"
    end
  end
end
