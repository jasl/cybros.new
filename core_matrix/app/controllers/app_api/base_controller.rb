module AppAPI
  class BaseController < ActionController::API
    include ActionController::Cookies
    include ActionController::RequestForgeryProtection
    include Rails.application.routes.url_helpers
    include APIErrorRendering
    include InstallationScopedLookup
    include SessionAuthentication

    before_action :authenticate_session!
    before_action :verify_cookie_backed_session_csrf!
    rescue_from SessionAuthentication::SessionRequired do |error|
      render json: { error: error.message }, status: :unauthorized
    end
    rescue_from ActionController::InvalidCrossOriginRequest do |error|
      render json: { error: error.message }, status: :unprocessable_entity
    end

    private

    def verify_cookie_backed_session_csrf!
      return if request.get? || request.head? || request.options?
      return unless protect_against_forgery?
      return unless session_authenticated_via_cookie?
      return if verified_request?

      raise ActionController::InvalidCrossOriginRequest, "csrf token is invalid"
    end

    def current_installation_id
      current_user.installation_id
    end

    def find_accessible_execution_runtime!(execution_runtime_id)
      find_execution_runtime!(execution_runtime_id)
    end

    def find_launchable_agent!(agent_id, execution_runtime: AppSurface::Policies::AgentLaunchability::DEFAULT_RUNTIME)
      agent = find_agent!(agent_id)
      raise ActiveRecord::RecordNotFound, "Couldn't find Agent" unless AppSurface::Policies::AgentLaunchability.call(
        user: current_user,
        agent: agent,
        execution_runtime: execution_runtime
      )

      agent
    end

    def find_workspace_agent!(workspace_agent_id, workspace: nil, launchable_only: false)
      if workspace.present? && workspace.association(:workspace_agents).loaded?
        candidate = workspace.workspace_agents.find do |loaded_workspace_agent|
          loaded_workspace_agent.public_id == workspace_agent_id &&
            (!launchable_only || loaded_workspace_agent.active?)
        end
        return candidate if candidate.present?
      end

      scope = WorkspaceAgent
        .joins(:workspace)
        .where(
          installation_id: current_user.installation_id,
          public_id: workspace_agent_id,
          workspaces: {
            user_id: current_user.id,
            privacy: "private",
          }
        )
        .includes(:agent, :default_execution_runtime, :workspace)
      scope = scope.where(workspace: workspace) if workspace.present?
      scope = scope.where(lifecycle_state: "active") if launchable_only

      scope.first || raise(ActiveRecord::RecordNotFound, "Couldn't find WorkspaceAgent")
    end

    def find_launchable_workspace_agent!(workspace_agent_id, execution_runtime: AppSurface::Policies::AgentLaunchability::DEFAULT_RUNTIME)
      workspace_agent = find_workspace_agent!(workspace_agent_id, launchable_only: true)
      raise ActiveRecord::RecordNotFound, "Couldn't find WorkspaceAgent" unless AppSurface::Policies::AgentLaunchability.call(
        user: current_user,
        agent: workspace_agent.agent,
        workspace_agent: workspace_agent,
        execution_runtime: execution_runtime
      )

      workspace_agent
    end

    def workspace_lookup_scope
      Workspace
        .accessible_to_user(current_user)
        .includes(workspace_agents: [:agent, :default_execution_runtime])
    end

    def agent_lookup_scope
      Agent.visible_to_user(current_user).eager_load(:default_execution_runtime)
    end

    def execution_runtime_lookup_scope
      ExecutionRuntime.visible_to_user(current_user)
    end

    def conversation_lookup_scope(workspace: nil)
      scope = Conversation
        .joins(:workspace_agent, :workspace)
        .where(
          installation_id: current_user.installation_id,
          deletion_state: "retained",
          workspaces: {
            user_id: current_user.id,
            privacy: "private",
          }
        )
      scope = scope.where(workspace_agents: { workspace_id: workspace.id }) if workspace.present?
      scope
    end

    def method_response(method_id:, **payload)
      AppSurface::MethodResponse.call(method_id: method_id, **payload)
    end

    def render_method_response(method_id:, status: :ok, **payload)
      render json: method_response(method_id: method_id, **payload), status: status
    end

    def serialize_message(message, conversation_public_id: nil, turn_public_id: nil)
      {
        "id" => message.public_id,
        "conversation_id" => conversation_public_id || message.conversation.public_id,
        "turn_id" => turn_public_id || message.turn.public_id,
        "role" => message.role,
        "slot" => message.slot,
        "variant_index" => message.variant_index,
        "content" => message.content,
        "attachments" => message.message_attachments.sort_by(&:id).map { |attachment| serialize_message_attachment(attachment) },
      }
    end

    def serialize_message_attachment(attachment, include_download_url: false, host: request.base_url)
      payload = {
        "attachment_id" => attachment.public_id,
        "kind" => attachment.message.user? ? "user_upload" : "generated_output",
        "filename" => attachment.file.filename.to_s,
        "content_type" => attachment.file.blob.content_type,
        "byte_size" => attachment.file.blob.byte_size,
        "publication_role" => Attachments::CreateForMessage.publication_role_for(attachment),
        "origin_attachment_id" => attachment.origin_attachment&.public_id,
        "origin_message_id" => attachment.origin_message&.public_id,
      }.compact

      return payload unless include_download_url

      payload.merge(
        "blob_signed_id" => attachment.file.blob.signed_id(expires_in: Attachments::CreateForMessage.signed_url_expires_in),
        "download_url" => Attachments::CreateForMessage.signed_download_url(attachment: attachment, host: host)
      )
    end
  end
end
